#!/bin/bash

# load some functions
. /opt/bunkerized-nginx/entrypoint/utils.sh

# self signed certs for sites
files=$(has_value GENERATE_SELF_SIGNED_SSL yes)
if [ "$files" != "" ] ; then
	for file in $files ; do
		site=$(echo $file | cut -f 4 -d '/')
		dest="/etc/nginx/"
		if [ "$site" != "site.env" ] ; then
			dest="${dest}/${site}/"
		fi
		SELF_SIGNED_SSL_EXPIRY="$(sed -nE 's/^SELF_SIGNED_SSL_EXPIRY=(.*)$/\1/p' $file)"
		SELF_SIGNED_SSL_COUNTRY="$(sed -nE 's/^SELF_SIGNED_SSL_COUNTRY=(.*)$/\1/p' $file)"
		SELF_SIGNED_SSL_STATE="$(sed -nE 's/^SELF_SIGNED_SSL_STATE=(.*)$/\1/p' $file)"
		SELF_SIGNED_SSL_CITY="$(sed -nE 's/^SELF_SIGNED_SSL_CITY=(.*)$/\1/p' $file)"
		SELF_SIGNED_SSL_ORG="$(sed -nE 's/^SELF_SIGNED_SSL_ORG=(.*)$/\1/p' $file)"
		SELF_SIGNED_SSL_OU="$(sed -nE 's/^SELF_SIGNED_SSL_OU=(.*)$/\1/p' $file)"
		SELF_SIGNED_SSL_CN="$(sed -nE 's/^SELF_SIGNED_SSL_CN=(.*)$/\1/p' $file)"
		/opt/bunkerized-nginx/jobs/main.py --name self-signed-cert --dst_cert "${dest}self-cert.pem" --dst_key "${dest}self-key.pem" --expiry "$SELF_SIGNED_SSL_EXPIRY" --subj "/C=$SELF_SIGNED_SSL_COUNTRY/ST=$SELF_SIGNED_SSL_STATE/L=$SELF_SIGNED_SSL_CITY/O=$SELF_SIGNED_SSL_ORG/OU=$SELF_SIGNED_SSL_OU/CN=$SELF_SIGNED_SSL_CN"
	done
fi

# self signed cert for default server
if [ "$(has_value AUTO_LETS_ENCRYPT yes)" != "" ] || [ "$(has_value GENERATE_SELF_SIGNED_SSL yes)" != "" ] || [ "$(has_value USE_CUSTOM_HTTPS yes)" != "" ] ; then
	SELF_SIGNED_SSL_EXPIRY="999"
	SELF_SIGNED_SSL_COUNTRY="US"
	SELF_SIGNED_SSL_STATE="Utah"
	SELF_SIGNED_SSL_CITY="Lehi"
	SELF_SIGNED_SSL_ORG="Your Company, Inc."
	SELF_SIGNED_SSL_OU="IT"
	SELF_SIGNED_SSL_CN="www.yourdomain.com"
	/opt/bunkerized-nginx/jobs/main.py --name self-signed-cert --dst_cert "/etc/nginx/default-cert.pem" --dst_key "/etc/nginx/default-key.pem" --expiry "$SELF_SIGNED_SSL_EXPIRY" --subj "/C=$SELF_SIGNED_SSL_COUNTRY/ST=$SELF_SIGNED_SSL_STATE/L=$SELF_SIGNED_SSL_CITY/O=$SELF_SIGNED_SSL_ORG/OU=$SELF_SIGNED_SSL_OU/CN=$SELF_SIGNED_SSL_CN"
fi

# certbot
files=$(has_value AUTO_LETS_ENCRYPT yes)
if [ "$files" != "" ] ; then
	for file in $files ; do
		if [ "$(echo "$file" | grep 'site.env$')" = "" ] ; then
			continue
		fi
		SERVER_NAME="$(sed -nE 's/^SERVER_NAME=(.*)$/\1/p' $file)"
		FIRST_SERVER="$(echo $SERVER_NAME | cut -d ' ' -f 1)"
		EMAIL_LETS_ENCRYPT="$(sed -nE 's/^EMAIL_LETS_ENCRYPT=(.*)$/\1/p' $file)"
		USE_STAGING="$(grep "^USE_LETS_ENCRYPT_STAGING=yes$" $file)"
		if [ "$EMAIL_LETS_ENCRYPT" = "" ] ; then
			EMAIL_LETS_ENCRYPT="contact@${FIRST_SERVER}"
		fi
		if [ "$USE_STAGING" = "" ] ; then
			/opt/bunkerized-nginx/jobs/main.py --name certbot-new --domain "$(echo -n $SERVER_NAME | sed 's/ /,/g')" --email "$EMAIL_LETS_ENCRYPT"
		else
			/opt/bunkerized-nginx/jobs/main.py --name certbot-new --domain "$(echo -n $SERVER_NAME | sed 's/ /,/g')" --email "$EMAIL_LETS_ENCRYPT" --staging
		fi
	done
fi


# GeoIP
if [ "$(has_value BLACKLIST_COUNTRY ".\+")" != "" ] || [ "$(has_value WHITELIST_COUNTRY ".\+")" != "" ] ; then
	/opt/bunkerized-nginx/jobs/main.py --name geoip --cache
fi

# User-Agents
if [ "$(has_value BLOCK_USER_AGENT yes)" != "" ] ; then
	/opt/bunkerized-nginx/jobs/main.py --name user-agents --cache
fi

# Referrers
if [ "$(has_value BLOCK_REFERRER yes)" != "" ] ; then
	/opt/bunkerized-nginx/jobs/main.py --name referrers --cache
fi

# exit nodes
if [ "$(has_value BLOCK_TOR_EXIT_NODE yes)" != "" ] ; then
	/opt/bunkerized-nginx/jobs/main.py --name exit-nodes --cache
fi

# proxies
if [ "$(has_value BLOCK_PROXIES yes)" != "" ] ; then
	/opt/bunkerized-nginx/jobs/main.py --name proxies --cache
fi

# abusers
if [ "$(has_value BLOCK_ABUSERS yes)" != "" ] ; then
	/opt/bunkerized-nginx/jobs/main.py --name abusers --cache
fi

# remote API
if [ "$(has_value USE_REMOTE_API yes)" != "" ] ; then
	/opt/bunkerized-nginx/jobs/main.py --name remote-api-register --cache --server "$(grep '^REMOTE_API_SERVER=' /etc/nginx/global.env | cut -d '=' -f 2)" --version "$(cat /opt/bunkerized-nginx/VERSION)"
	if [ $? -eq 0 ] ; then
		/opt/bunkerized-nginx/jobs/main.py --name remote-api-database --cache --server "$(grep '^REMOTE_API_SERVER=' /etc/nginx/global.env | cut -d '=' -f 2)" --version "$(cat /opt/bunkerized-nginx/VERSION)" --id "$(cat /opt/bunkerized-nginx/cache/machine.id)"
	fi
fi
