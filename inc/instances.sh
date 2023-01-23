#!/bin/sh
: '''
Managing Script :: Source Dedicated Server (srcds)

Copyright (c) 2021-23 etkaar <https://github.com/etkaar/srcds>

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

# Validates variables for selected instance
instance_GET_CONFIG_VARS() {
	SELECTED_INSTANCE_ID="$1"
	
	# All configuration variables for an instance
	# NOTE: INSTANCE_ADDITIONAL_ARGUMENTS will be the rest of the line
	read -r \
	INSTANCE_ID \
	INSTANCE_SERVER_APP_ID \
	INSTANCE_IPV4_ADDRESS \
	INSTANCE_PORT \
	INSTANCE_MAP \
	INSTANCE_MAX_PLAYERS \
	INSTANCE_STATUS \
	INSTANCE_PRIORITY \
	INSTANCE_CPU_CORES \
	INSTANCE_ADDITIONAL_ARGUMENTS \
	<<-EOF
	$(printf '%s\n' "$CFG_INSTANCES_CONTENT" | grep "$SELECTED_INSTANCE_ID[[:space:]]")
	EOF
	
	# Metainformation for this Server App ID
	LINE="$(printf '%s\n' "$CFG_GAMES_CONTENT" | grep "$INSTANCE_SERVER_APP_ID[[:space:]]")"
	
	INSTANCE_GAME_SHORTNAME="$(printf '%s' "$LINE" | awk '{print $2}')"
}

# Sets variables for selected instance and validates them
instance_GET_AND_VALIDATE_CONFIG_VARS() {
	SELECTED_INSTANCE_ID="$1"
	
	# Get all configuration variables of this instance
	instance_GET_CONFIG_VARS "$SELECTED_INSTANCE_ID"

	if [ "$INSTANCE_ID" = "all" ]
	then
		func_EXIT_ERROR 1 "Instance <$SELECTED_INSTANCE_ID> is using reserved keyword as name." "  $CFG_INSTANCES_PATH"
	fi

	if ! func_IS_UNSIGNED_INTEGER "$INSTANCE_SERVER_APP_ID"
	then
		func_EXIT_ERROR 1 "Invalid app id '$INSTANCE_SERVER_APP_ID' for instance <$SELECTED_INSTANCE_ID> in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if ! func_IS_IPV4_ADDRESS "$INSTANCE_IPV4_ADDRESS"
	then
		func_EXIT_ERROR 1 "Invalid IPv4 address '$INSTANCE_IPV4_ADDRESS' for instance <$SELECTED_INSTANCE_ID> in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if ! func_IS_UNSIGNED_INTEGER "$INSTANCE_PORT" || [ "$INSTANCE_PORT" -lt 1 ] || [ "$INSTANCE_PORT" -gt 65535 ]
	then
		func_EXIT_ERROR 1 "Invalid port '$INSTANCE_PORT' for instance <$SELECTED_INSTANCE_ID> in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if ! func_IS_UNSIGNED_INTEGER "$INSTANCE_MAX_PLAYERS" || [ "$INSTANCE_MAX_PLAYERS" -lt 1 ] || [ "$INSTANCE_MAX_PLAYERS" -gt 64 ]
	then
		func_EXIT_ERROR 1 "Invalid max players value '$INSTANCE_MAX_PLAYERS' for instance <$SELECTED_INSTANCE_ID> in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if [ ! "$INSTANCE_STATUS" = "always-online" ]
	then
		func_EXIT_ERROR 1 "Status must be set to 'always-online' for instance <$SELECTED_INSTANCE_ID> in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if [ ! "$INSTANCE_PRIORITY" = "default" ] && [ ! "$INSTANCE_PRIORITY" = "real-time" ]
	then
		func_EXIT_ERROR 1 "Priority must either be set to 'default' or 'real-time' for instance <$SELECTED_INSTANCE_ID> in:" "  $CFG_INSTANCES_PATH"
	fi
	
	# Validate Server App ID
	if [ "$INSTANCE_GAME_SHORTNAME" = "" ]
	then
		func_EXIT_ERROR 1 "Could not find shortname for Server App ID $INSTANCE_SERVER_APP_ID, please see:" "  $CFG_GAMES_PATH"
	fi
}

# Sets required variables to start, stop or check an instance
instance_GET_INSTANCE_VARS() {
	SELECTED_INSTANCE_ID="$1"
	
	# Get all configuration variables of this instance
	instance_GET_CONFIG_VARS "$SELECTED_INSTANCE_ID"

	# Clear additional arguments if set to 'none'
	if [ "$INSTANCE_ADDITIONAL_ARGUMENTS" = "none" ]
	then
		INSTANCE_ADDITIONAL_ARGUMENTS=""
	else
		# Prepend a space
		INSTANCE_ADDITIONAL_ARGUMENTS=" $INSTANCE_ADDITIONAL_ARGUMENTS"
	fi

	# Commands
	SCREEN_NAME="${CVAR_SCREEN_NAME_PREFIX}$SELECTED_INSTANCE_ID"
	CMD_START="env RDTSC_FREQUENCY=disabled ./srcds_run -game $INSTANCE_GAME_SHORTNAME -ip $INSTANCE_IPV4_ADDRESS -port $INSTANCE_PORT +map $INSTANCE_MAP -maxplayers ${INSTANCE_MAX_PLAYERS}$INSTANCE_ADDITIONAL_ARGUMENTS -steam_dir ../tools/steam -steamcmd_script ../tools/steam/steamcmd.sh -dir ."
	CMD_STOP="screen -S $SCREEN_NAME -p 0 -X stuff $'\003'"

	# Search string we use to find the process. So we don't need
	# any pid file to check if the process is running or not.
	# NOTE: That is the id of the screen process, not the gameserver 
	MAIN_PROCESS_SEARCH_STRING="SCREEN -L -d -m -S $SCREEN_NAME "
	SUB_PROCESS_SEARCH_STRING="./srcds_linux -game $INSTANCE_GAME_SHORTNAME -ip $INSTANCE_IPV4_ADDRESS -port $INSTANCE_PORT "

	# Path of pid file
	INSTANCE_MAIN_PID_FILE="./.process.instance-$SELECTED_INSTANCE_ID.pid"
	
	# Instance path
	INSTANCE_PATH="$CVAR_INSTANCES_PATH/$SELECTED_INSTANCE_ID"
}

# Process id of the high privileged screen process. This is usually we want.
instance_GET_MAIN_PID() {
	INSTANCE_MAIN_PROCESS_ID="$(pgrep -f "^$MAIN_PROCESS_SEARCH_STRING")"
}

# Process id of the gameserver process run by <User:Group>. Used for taskset or priority.
instance_GET_SUB_PID() {
	INSTANCE_SUB_PROCESS_ID="$(pgrep -f "^$SUB_PROCESS_SEARCH_STRING")"
}

# Validate permissions for an instance
instance_VALIDATE_PERMISSIONS() {
	UPDATE="$1"
	SELECTED_INSTANCE_ID="$2"
	SELECTED_INSTANCE_PATH="$CVAR_INSTANCES_PATH/$SELECTED_INSTANCE_ID"

	if [ "$UPDATE" = "full" ]
	then
		# Change owner/group
		chown -R "$CVAR_USER:$CVAR_GROUP" "$SELECTED_INSTANCE_PATH"
		
		# Dirs and files
		find "$SELECTED_INSTANCE_PATH" -type d -exec chmod "$DEFAULT_DIR_PERMISSIONS" -- {} +	
		find "$SELECTED_INSTANCE_PATH" -type f -exec chmod "$DEFAULT_FILE_PERMISSIONS" -- {} +
	fi
	
	# Make specific files executable
	chmod "$DEFAULT_DIR_PERMISSIONS" "$INSTANCE_PATH/srcds_run"
	chmod "$DEFAULT_DIR_PERMISSIONS" "$INSTANCE_PATH/srcds_linux"
}

# Find out if instance is installed
instance_IS_INSTALLED() {
	SELECTED_INSTANCE_ID="$1"
	
	# Get instance vars (such as the screen name)
	instance_GET_INSTANCE_VARS "$SELECTED_INSTANCE_ID"	
	
	if [ -d "$INSTANCE_PATH" ]
	then
		if [ ! -e "$INSTANCE_PATH/srcds_linux" ] || [ ! -e "$INSTANCE_PATH/srcds_run" ]
		then
			# Something is wrong with the installation
			return 2
		fi

		# Installed
		return 0
	fi
	
	# Not installed
	return 1
}

# Find out if instance is currently running
instance_IS_RUNNING() {
	SELECTED_INSTANCE_ID="$1"
	
	# Get instance vars (such as the screen name)
	instance_GET_INSTANCE_VARS "$SELECTED_INSTANCE_ID"
	
	# Get main process id
	instance_GET_MAIN_PID	
	
	# Running
	if [ ! "$INSTANCE_MAIN_PROCESS_ID" = "" ]
	then
		return 0
	fi
	
	# Not running
	return 1
}

# Get a list of all instances
instance_GET_LIST() {
	INSTANCES_LIST="$(printf '%s\n' "$CFG_INSTANCES_CONTENT" | awk '{print $1}')"
	
	printf '%s\n' "$INSTANCES_LIST"
}
