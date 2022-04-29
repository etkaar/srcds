#!/bin/sh
: '''
Managing Script :: Source Dedicated Server (srcds)

Copyright (c) 2021-22 etkaar <https://github.com/etkaar/srcds>
Version 1.0.0 (April, 29th 2022)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
OR OTHER DEALINGS IN THE SOFTWARE.
'''

# Notes
: """
	local VAR
		The local keyword is not POSIX-compliant, therefore not used. Instead,
		if required and where suitable, we make use of a subshell.
"""

# If colors are enabled
func_COLORS_ENABLED() {
	# 0 in this context means true (and not false),
	# because it is an exit code – not a boolean.
	return 0
}

# Truncate file
func_TRUNCATE() {
	: > "$1"
}

# Message to STDOUT
func_STDOUT() {
	# Places a newline character after each word ("...")
	printf '%s\n' "$@"
}

# Message to STDERR
func_STDERR() {
	>&2 printf '%s\n' "$@"
}

# Only for internal use
internal_PRINT() {
	CHANNEL="$1"
	COLOR_CODE="$2"
	
	# Remove all arguments, but not the message
	shift 2
	
	COLOR_START="\e[${COLOR_CODE}m"
	COLOR_RESET="\e[0m"
	
	if func_COLORS_ENABLED
	then
		if [ "$CHANNEL" = "1" ]
		then
			printf "$COLOR_START"
		elif [ "$CHANNEL" = "2" ]
		then
			>&2 printf "$COLOR_START"
		fi
	fi
	
	if [ "$CHANNEL" = "1" ]
	then
		func_STDOUT "$@"
	elif [ "$CHANNEL" = "2" ]
	then
		func_STDERR "$@"
	fi
	
	if func_COLORS_ENABLED
	then
		if [ "$CHANNEL" = "1" ]
		then
			printf "$COLOR_RESET"
		elif [ "$CHANNEL" = "2" ]
		then
			>&2 printf "$COLOR_RESET"
		fi
	fi
}

# STDOUT: Success
func_PRINT_SUCCESS() {
	internal_PRINT "1" "32" "$@"
}

# STDOUT: Info
func_PRINT_INFO() {
	internal_PRINT 2 35 "$@"
}

# STDERR: Debug
func_PRINT_DEBUG() {
	internal_PRINT 2 35 "$@"
}

# STDERR: Warning
func_PRINT_WARNING() {
	internal_PRINT 2 33 "$@"
}

# STDERR: Error
func_PRINT_ERROR() {
	internal_PRINT 2 31 "$@"
}

# Prints message to STDOUT and exit(0)
func_EXIT_SUCCESS() {
	func_PRINT_SUCCESS "$@"
	func_TIDY_UP
	
	exit 0
}

# Prints error message to STDERR and exit
func_EXIT_ERROR() {
	EXIT_CODE="$1"
	
	# Remove first argument
	shift
	
	func_TIDY_UP
	
	func_PRINT_ERROR "$@"
	exit "$EXIT_CODE"
}

# Prints warning message to STDERR and exit
func_EXIT_WARNING() {
	EXIT_CODE="$1"
	
	# Remove first argument
	shift
	
	func_TIDY_UP
	
	func_PRINT_WARNING "$@"
	exit "$EXIT_CODE"
}

# Intend all lines
func_INDENT_ALL_LINES() {
	LINES="$1"
	
	for LINE in $LINES
	do
		printf '  %s\n' "$LINE"
	done
}

# Check for missing packages
func_CHECK_DEPENDENCIES() {
	LIST="$1"
	RETURN_ONLY="$2"

	for PACKAGE_NAME in $LIST
	do
		# Not installed
		if ! dpkg-query -s "$PACKAGE_NAME" >/dev/null 2>&1
		then
			if [ "$RETURN_ONLY" = "1" ]
			then
				printf '%s ' "$PACKAGE_NAME"
			else
				func_INSTALL_PACKAGES "$PACKAGE_NAME"
			fi
		fi
	done
}

# Install packages
func_INSTALL_PACKAGES() {
	LIST="$1"
	
	for PACKAGE_NAME in $LIST
	do
		apt install -y "$PACKAGE_NAME"
	done
}

# Simple readin of a file, but comments are removed
func_READ_CONFIG_FILE() {
	CONFIG_FILE_PATH="$1"
	CONTENT="$(cat "$CONFIG_FILE_PATH" | egrep -v "^\s*(#|$)")"
	
	printf '%s\n' "$CONTENT"
}

# Read value from configuration by given key
func_READ_FROM_CONFIG() {
	CONFIG_FILE_PATH="$1"
	CONFIG_VAR_KEY="$2"
	
	RESULT="$(func_READ_CONFIG_FILE "$CONFIG_FILE_PATH" | grep "$CONFIG_VAR_KEY[[:space:]]" | awk '{print $2}')"
	
	# Remove leading or trailing quotes
	RESULT=${RESULT#[\"]}
	RESULT=${RESULT%[\"]}
	
	printf '%s\n' "$RESULT"
}

# Make sure required configuration variables exist and are unique
func_ENSURE_CONFIG_VARS() {
	CONFIG_FILE_PATH="$1"
	REQUIRED_CONFIG_VARS="$2"
	
	# Read in configuration file
	CONFIG_FILE_CONTENT="$(func_READ_CONFIG_FILE "$CONFIG_FILE_PATH")"
	
	# Passthrough all required configuration variables (separated by space)
	for CONFIG_VAR_KEY in $(printf '%s' "$REQUIRED_CONFIG_VARS" | sed "s/ /\n/g")
	do
		RESULT="$(printf '%s\n' "$CONFIG_FILE_CONTENT" | grep "$CONFIG_VAR_KEY[[:space:]]" | awk '{print $2}')"
		MATCHES="$(printf '%s\n' "$RESULT" | wc -l)"
		
		# Must be present
		if [ "$RESULT" = "" ]
		then
			printf '%s\n' "Required configuration variable '$CONFIG_VAR_KEY' missing in:" "  $CONFIG_FILE_PATH"
			return 1
		fi
		
		# Must be unique
		if [ "$MATCHES" -gt 1 ]
		then
			printf '%s\n' "Multiple occurrences of configuration variable '$CONFIG_VAR_KEY' found in:" "  $CONFIG_FILE_PATH"
			return 2
		fi
	done

	return 0
}

# Get number of occurrences (n) of a substring (needle) in another string (haystack) 
func_SUBSTR_COUNT() {
	SUBSTRING="$1"
	STRING="$2"
	
	printf '%s\n' "$STRING" | awk -F"$SUBSTRING" '{print NF-1}'
}

# Check if string is an unsigned integer (also +1 is not considered as be valid)
func_IS_UNSIGNED_INTEGER() {
	NUMBER="$1"
	
	case "$NUMBER" in
		*[!0-9]* | '')
			return 1
		;;
	esac
	
	return 0
}

# Check if string is an signed *or* unsigned integer
func_IS_INTEGER() {
	NUMBER="$1"
	
	# Remove leading - or +
	func_IS_UNSIGNED_INTEGER ${NUMBER#[-+]}
}

# Check if given string is an IPv4 address
# WARNING: This is nothing more than a *weak* plausibility check.
func_IS_IPV4_ADDRESS() {
	HOSTNAME_SUBNET_OR_ADDRESS="$1"
	
	# We need exactly three (3) dots (.)
	COUNT="$(func_SUBSTR_COUNT "." "$HOSTNAME_SUBNET_OR_ADDRESS")"
	
	if [ ! "$COUNT" = 3 ]
	then
		return 1
	fi
	
	RETVAL=0
	
	# Groups are separated by a dot (.)
	func_SET_IFS '\n'
	
	for GROUP in $(printf '%s' "$HOSTNAME_SUBNET_OR_ADDRESS" | awk -F'/' '{print $1}' | sed "s/\./\n/g")
	do
		# Check if group is an integer number
		if ! func_IS_UNSIGNED_INTEGER "$GROUP"
		then
			RETVAL=1
			break
		fi
		
		# Validate range (0-255)
		if [ "$GROUP" -lt 0 ] || [ "$GROUP" -gt 255 ]
		then
			RETVAL=1
			break
		fi
	done
	
	func_RESTORE_IFS
	
	return "$RETVAL"
}

# Find out if user exists
func_USER_EXISTS() {
	USER="$1"
	
	if id -u "$USER" >/dev/null 2>&1
	then
		return 0
	fi
	
	return 1
}

# Find out if group exists
func_GROUP_EXISTS() {
	USER="$1"
	
	if getent group "$GROUP" >/dev/null 2>&1
	then
		return 0
	fi
	
	return 1
}

# Prevents the process from running multiple times at the same time
func_BLOCK_PROCESS() {
	# Name of process (e.g. 'update')
	PROCESS_NAME="$1"
	PATH_FOR_PID_FILE="$2"
	
	# Path for pid file
	GLOBAL_PIDFILE="$PATH_FOR_PID_FILE/.$PROCESS_NAME.pid"

	# Validate process is not already running
	if [ -f "$GLOBAL_PIDFILE" ]
	then
		PID="$(cat "$GLOBAL_PIDFILE")"
		
		# Process is already running
		if kill -0 "$PID" 2>/dev/null
		then
			# Do not use 'func_EXIT_ERROR' because it will remove the pid file
			func_PRINT_ERROR "Process '$PROCESS_NAME' still running (pid $PID)"
			exit 1
		else
			if rm "$GLOBAL_PIDFILE"
			then
				func_PRINT_WARNING "Removed abandoned .pid file."
			fi
		fi
		
	fi

	# Store current pid into file
	printf "$$" > "$GLOBAL_PIDFILE"
}

# Remove pid file if exists
func_RELEASE_PROCESS() {
	if [ ! "$GLOBAL_PIDFILE" = "" ] && [ -f "$GLOBAL_PIDFILE" ]
	then
		rm "$GLOBAL_PIDFILE"
	fi
}

# Check if user crontab exists
func_USER_CRONTAB_EXISTS() {
	CRONTAB_LINE="$1"
	
	COMMAND="$(printf '%s\n' "$CRONTAB_LINE" | cut -d' ' -f6-)"
	LINE="$(crontab -l 2>/dev/null | grep "$COMMAND\$")"
	
	if [ ! "$LINE" = "" ]
	then
		return 0
	else
		return 1
	fi
}

# Add user crontab if not exists
func_ADD_USER_CRONTAB() {
	CRONTAB_LINE="$1"
	(crontab -l 2>/dev/null; printf '%s\n' "$CRONTAB_LINE") | crontab -
}

# This is a workaround, because neither <IFS=\'n'> or <IFS=$(printf '\n')> will work in Dash
func_SET_IFS() {
	NEW_IFS="$1"

	eval "$(printf "IFS='$NEW_IFS'")"
}

# Don't forget to unset after using func_SET_IFS() if not executed within a subshell
func_RESTORE_IFS() {
	unset IFS
}

# Deletes files when script is finished
func_TIDY_UP() {
	# Delete process pid file if exists
	func_RELEASE_PROCESS
	
	# Delete .tmp dir if empty
	rmdir "$TMP_PATH" 2>/dev/null
}
