#!/bin/bash

# check rx or rwx permissions on a folder
function check_permissions() {
	if [ "$1" = "rx" ] ; then
		[ -r "$2" ] && [ -x "$2" ]
		return $?
	fi
	[ -r "$2" ] && [ -x "$2" ] && [ -w "$2" ]
	return $?
}

# replace pattern in file
function replace_in_file() {
	# escape slashes
	pattern=$(echo "$2" | sed "s/\//\\\\\//g")
	replace=$(echo "$3" | sed "s/\//\\\\\//g")
	sed "s/$pattern/$replace/g" "$1" > /tmp/sed
	cat /tmp/sed > "$1"
	rm /tmp/sed
}

# convert space separated values to LUA
function spaces_to_lua() {
	for element in $1 ; do
		if [ "$result" = "" ] ; then
			result="\"${element}\""
		else
			result="${result}, \"${element}\""
		fi
	done
	echo "$result"
}

# check if at least one env var (global or multisite) has a specific value
function has_value() {
	envs=$(find /etc/nginx -name "*.env")
	for file in $envs ; do
		if [ "$(grep "^${1}=${2}$" $file)" != "" ] ; then
			echo "$file"
		fi
	done
}

# log to stdout
function log() {
	when="$(date '+[%Y-%m-%d %H:%M:%S]')"
	category="$1"
	severity="$2"
	message="$3"
	echo "$when $category - $severity - $message"
}

