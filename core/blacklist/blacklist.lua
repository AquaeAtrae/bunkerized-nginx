local _M = {}
_M.__index = _M

local utils		= require "utils"
local datastore	= require "datastore"
local logger	= require "logger"
local cjson		= require "cjson"
local ipmatcher	= require "resty.ipmatcher"

function _M.new()
	local self = setmetatable({}, _M)
	return self, nil
end

function _M:init()
	-- Check if init is needed
	local init_needed, err = utils.has_variable("USE_BLACKLIST", "yes")
	if init_needed == nil then
		return false, err
	end
	if not init_needed then
		return true, "no service uses Blacklist, skipping init"
	end
	-- Read blacklists
	local blacklists = {
		["IP"] = {},
		["RDNS"] = {},
		["ASN"] = {},
		["USER_AGENT"] = {},
		["URI"] = {}
	}
	local i = 0
	for kind, _ in pairs(blacklists) do
		local f, err = io.open("/opt/bunkerweb/cache/blacklist/" .. kind .. ".list", "r")
		if f then
			for line in f:lines() do
				table.insert(blacklists[kind], line)
				i = i + 1
			end
			f:close()
		end
	end
	-- Load them into datastore
	local ok, err = datastore:set("plugin_blacklist_list", cjson.encode(blacklists))
	if not ok then
		return false, "can't store Blacklist list into datastore : " .. err
	end
	return true, "successfully loaded " .. tostring(i) .. " bad IP/network/rDNS/ASN/User-Agent/URI"
end

function _M:access()
	-- Check if access is needed
	local access_needed, err = utils.get_variable("USE_BLACKLIST")
	if access_needed == nil then
		return false, err
	end
	if access_needed ~= "yes" then
		return true, "Blacklist not activated"
	end

	-- Check the cache
	local cached_ip, err = self:is_in_cache("ip" .. ngx.var.remote_addr)
	if cached_ip and cached_ip ~= "ok" then
		return true, "IP is in blacklist cache (info = " .. cached_ip .. ")", true, ngx.HTTP_FORBIDDEN
	end
	local cached_uri, err = self:is_in_cache("uri" .. ngx.var.uri)
	if cached_uri and cached_uri ~= "ok" then
		return true, "URI is in blacklist cache (info = " .. cached_uri .. ")", true, ngx.HTTP_FORBIDDEN
	end
	local cached_ua = true
	if ngx.var.http_user_agent then
		cached_ua, err = self:is_in_cache("ua" .. ngx.var.http_user_agent)
		if cached_ua and cached_ua ~= "ok" then
			return true, "User-Agent is in blacklist cache (info = " .. cached_ua .. ")", true, ngx.HTTP_FORBIDDEN
		end
	end
	if cached_ip and cached_uri and cached_ua then
		return true, "full request is in blacklist cache (not blacklisted)", nil, nil
	end

	-- Get list
	local data, err = datastore:get("plugin_blacklist_list")
	if not data then
		return false, "can't get Blacklist list : " .. err, false, nil
	end
	local ok, blacklists = pcall(cjson.decode, data)
	if not ok then
		return false, "error while decoding blacklists : " .. blacklists, false, nil
	end

	-- Return value
	local ret, ret_err = true, "success"
	
	-- Check if IP is in IP/net blacklist
	local ip_net, err = utils.get_variable("BLACKLIST_IP")
	if ip_net and ip_net ~= "" then
		for element in ip_net:gmatch("%S+") do
			table.insert(blacklists["IP"], element)
		end
	end
	if not cached_ip then
		local ipm, err = ipmatcher.new(blacklists["IP"])
		if not ipm then
			ret = false
			ret_err = "can't instantiate ipmatcher " .. err
		else
			if ipm:match(ngx.var.remote_addr) then
				self:add_to_cache("ip" .. ngx.var.remote_addr, "ip/net")
				return ret, "client IP " .. ngx.var.remote_addr .. " is in blacklist", true, ngx.HTTP_FORBIDDEN
			end
		end
	end

	-- Check if rDNS is in blacklist
	local rdns_global, err = utils.get_variable("BLACKLIST_RDNS_GLOBAL")
	local check = true
	if not rdns_global then
		logger.log(ngx.ERR, "BLACKLIST", "Error while getting BLACKLIST_RDNS_GLOBAL variable : " .. err)
	elseif rdns_global == "yes" then
		check, err = utils.ip_is_global(ngx.var.remote_addr)
		if check == nil then
			logger.log(ngx.ERR, "BLACKLIST", "Error while getting checking if IP is global : " .. err)
		end
	end
	if not cached_ip and check then
		local rdns, err = utils.get_rdns(ngx.var.remote_addr)
		if not rdns then
			ret = false
			ret_err = "error while trying to get reverse dns : " .. err
		else
			local rdns_list, err = utils.get_variable("BLACKLIST_RDNS")
			if rdns_list and rdns_list ~= "" then
				for element in rdns_list:gmatch("%S+") do
					table.insert(blacklists["RDNS"], element)
				end
			end
			for i, suffix in ipairs(blacklists["RDNS"]) do
				if rdns:sub(-#suffix) == suffix then
					self:add_to_cache("ip" .. ngx.var.remote_addr, "rDNS " .. suffix)
					return ret, "client IP " .. ngx.var.remote_addr .. " is in blacklist (info = rDNS " .. suffix .. ")", true, ngx.HTTP_FORBIDDEN
				end
			end
		end
	end

	-- Check if ASN is in blacklist
	if not cached_ip then
		if utils.ip_is_global(ngx.var.remote_addr) then
			local asn, err = utils.get_asn(ngx.var.remote_addr)
			if not asn then
				ret = false
				ret_err = "error while trying to get asn number : " .. err
			else
				local asn_list, err = utils.get_variable("BLACKLIST_ASN")
				if asn_list and asn_list ~= "" then
					for element in asn_list:gmatch("%S+") do
						table.insert(blacklists["ASN"], element)
					end
				end
				for i, asn_bl in ipairs(blacklists["ASN"]) do
					if tostring(asn) == asn_bl then
						self:add_to_cache("ip" .. ngx.var.remote_addr, "ASN " .. tostring(asn))
						return ret, "client IP " .. ngx.var.remote_addr .. " is in blacklist (kind = ASN " .. tostring(asn) .. ")", true, ngx.HTTP_FORBIDDEN
					end
				end
			end
		end
	end

	-- IP is not blacklisted
	local ok, err = self:add_to_cache("ip" .. ngx.var.remote_addr, "ok")
	if not ok then
		ret = false
		ret_err = err
	end

	-- Check if User-Agent is in blacklist
	if not cached_ua and ngx.var.http_user_agent then
		local ua_list, err = utils.get_variable("BLACKLIST_USER_AGENT")
		if ua_list and ua_list ~= "" then
			for element in ua_list:gmatch("%S+") do
				table.insert(blacklists["USER_AGENT"], element)
			end
		end
		for i, ua_bl in ipairs(blacklists["USER_AGENT"]) do
			if ngx.var.http_user_agent:match(ua_bl) then
				self:add_to_cache("ua" .. ngx.var.http_user_agent, "UA " .. ua_bl)
				return ret, "client User-Agent " .. ngx.var.http_user_agent .. " is in blacklist (matched " .. ua_bl .. ")", true, ngx.HTTP_FORBIDDEN
			end
		end
		-- UA is not blacklisted
		local ok, err = self:add_to_cache("ua" .. ngx.var.http_user_agent, "ok")
		if not ok then
			ret = false
			ret_err = err
		end
	end

	-- Check if URI is in blacklist
	if not cached_uri then
		local uri_list, err = utils.get_variable("BLACKLIST_URI")
		if uri_list and uri_list ~= "" then
			for element in uri_list:gmatch("%S+") do
				table.insert(blacklists["URI"], element)
			end
		end
		for i, uri_bl in ipairs(blacklists["URI"]) do
			if ngx.var.uri:match(uri_bl) then
				self:add_to_cache("uri" .. ngx.var.uri, "URI " .. uri_bl)
				return ret, "client URI " .. ngx.var.uri .. " is in blacklist (matched " .. uri_bl .. ")", true, ngx.HTTP_FORBIDDEN
			end
		end
	end

	-- URI is not blacklisted
	local ok, err = self:add_to_cache("uri" .. ngx.var.uri, "ok")
	if not ok then
		ret = false
		ret_err = err
	end
	
	return ret, "IP is not in list (error = " .. ret_err .. ")", false, nil
end

function _M:is_in_cache(ele)
	local kind, err = datastore:get("plugin_blacklist_cache_" .. ngx.var.server_name .. ele)
	if not kind then
		if err ~= "not found" then
			logger.log(ngx.ERR, "BLACKLIST", "Error while accessing cache : " .. err)
		end
		return false, err
	end
	return kind, "success"
end

function _M:add_to_cache(ele, kind)
	local ok, err = datastore:set("plugin_blacklist_cache_" .. ngx.var.server_name .. ele, kind, 3600)
	if not ok then
		logger.log(ngx.ERR, "BLACKLIST", "Error while adding element to cache : " .. err)
		return false, err
	end
	return true, "success"
end

return _M
