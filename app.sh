#!/bin/sh
: '''
Managing Script :: Source Dedicated Server (srcds)

Copyright (c) 2021-23 etkaar <https://github.com/etkaar/srcds>
Version 1.0.1 (January, 20th 2023)

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
# Change working directory
ABSPATH="$(cd "$(dirname "$0")"; pwd -P)"
cd "$ABSPATH"

# Import generic functions
. ./inc/_defs.sh

if [ ! "$(whoami)" = "root" ]
then
	func_EXIT_ERROR 1 "You need to run this command as root."
fi

# Use example for this application
APPLICATION_USE_EXAMPLE_LINE="${0} [Instance ID (e.g. srv0, srv1, ...)] {status|check|start|stop|restart|install|update|fix-permissions}"

# Instance ID from command line
GIVEN_INSTANCE_ID="$1"

# Paths
APP_PATH="$ABSPATH/app"
CONF_PATH="$ABSPATH/conf"
LOG_PATH="$ABSPATH/log"
CACHE_PATH="$ABSPATH/.cache"
TMP_PATH="$ABSPATH/.tmp"

STEAMCMD_PATH="$CACHE_PATH/steamcmd"
STEAMCMD_DOWNLOAD_URL="https://media.steampowered.com/client/steamcmd_linux.tar.gz"

# Create directories if not exist
for CHECKPATH in "$LOG_PATH" "$CACHE_PATH" "$TMP_PATH"
do
	if [ ! -d "$CHECKPATH" ]
	then
		mkdir "$CHECKPATH"
	fi
done

# Configuration files
CFG_MAIN_PATH="$CONF_PATH/main.conf"
CFG_INSTANCES_PATH="$CONF_PATH/instances.conf"

CFG_INSTANCES_CONTENT="$(func_READ_CONFIG_FILE "$CFG_INSTANCES_PATH")"

# Sets variables for selected instance and validates them
local_GET_AND_VALIDATE_INSTANCE_CONFIG_VARS() {
	SELECTED_INSTANCE_ID="$1"
	
	# Get all configuration variables of this instance
	local_GET_INSTANCE_CONFIG_VARS "$SELECTED_INSTANCE_ID"
	
	if ! func_IS_UNSIGNED_INTEGER "$INSTANCE_SERVER_APP_ID"
	then
		func_EXIT_ERROR 1 "Invalid app id '$INSTANCE_SERVER_APP_ID' for instance '$SELECTED_INSTANCE_ID' in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if ! func_IS_IPV4_ADDRESS "$INSTANCE_IPV4_ADDRESS"
	then
		func_EXIT_ERROR 1 "Invalid IPv4 address '$INSTANCE_IPV4_ADDRESS' for instance '$SELECTED_INSTANCE_ID' in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if ! func_IS_UNSIGNED_INTEGER "$INSTANCE_PORT" || [ "$INSTANCE_PORT" -lt 1 ] || [ "$INSTANCE_PORT" -gt 65535 ]
	then
		func_EXIT_ERROR 1 "Invalid port '$INSTANCE_PORT' for instance '$SELECTED_INSTANCE_ID' in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if ! func_IS_UNSIGNED_INTEGER "$INSTANCE_MAX_PLAYERS" || [ "$INSTANCE_MAX_PLAYERS" -lt 1 ] || [ "$INSTANCE_MAX_PLAYERS" -gt 64 ]
	then
		func_EXIT_ERROR 1 "Invalid max players value '$INSTANCE_MAX_PLAYERS' for instance '$SELECTED_INSTANCE_ID' in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if [ ! "$INSTANCE_STATUS" = "always-online" ]
	then
		func_EXIT_ERROR 1 "Status must be set to 'always-online' for instance '$SELECTED_INSTANCE_ID' in:" "  $CFG_INSTANCES_PATH"
	fi
	
	if [ ! "$INSTANCE_PRIORITY" = "default" ]
	then
		func_EXIT_ERROR 1 "Priority must be set to 'default' for instance '$SELECTED_INSTANCE_ID' in:" "  $CFG_INSTANCES_PATH"
	fi
}

# Validates variables for selected instance
local_GET_INSTANCE_CONFIG_VARS() {
	SELECTED_INSTANCE_ID="$1"
	
	# Extracts the line for this instance of the configuration file
	LINE="$(printf '%s\n' "$CFG_INSTANCES_CONTENT" | grep "$SELECTED_INSTANCE_ID[[:space:]]")"

	# All configuration variables for an instance
	INSTANCE_SERVER_APP_ID="$(printf '%s' "$LINE" | awk '{print $2}')"
	INSTANCE_IPV4_ADDRESS="$(printf '%s' "$LINE" | awk '{print $3}')"
	INSTANCE_PORT="$(printf '%s' "$LINE" | awk '{print $4}')"
	INSTANCE_MAP="$(printf '%s' "$LINE" | awk '{print $5}')"
	INSTANCE_MAX_PLAYERS="$(printf '%s' "$LINE" | awk '{print $6}')"
	INSTANCE_STATUS="$(printf '%s' "$LINE" | awk '{print $7}')"
	INSTANCE_PRIORITY="$(printf '%s' "$LINE" | awk '{print $8}')"
}

local_VALIDATE_USER_AND_GROUP() {
	USER="$1"
	GROUP="$2"
	
	# Ensure user exists
	if ! func_USER_EXISTS "$USER"
	then
		func_EXIT_ERROR 1 "User '$USER' does not exist."
	fi

	if [ "$GROUP" = "" ]
	then
		GROUP="$USER"
	fi

	# Ensure group exists
	if ! func_GROUP_EXISTS "$GROUP"
	then
		func_EXIT_ERROR 1 "Group '$GROUP' does not exist."
	fi
}

local_FORCE_SHELL_FOR_USER() {
	USER="$1"
	SHELL="$2"
	
	# Force shell for user. Usually you want to disable login for the
	# unpriviligated user by using /usr/sbin/nologin (or /bin/false).
	CURRENT_SHELL="$(getent passwd "$USER" | awk -F':' '{print $7}')"

	if [ ! "$CURRENT_SHELL" = "$SHELL" ]
	then
		if usermod --shell "$SHELL" "$USER"
		then
			func_STDOUT "Changed shell for user '$USER' from '$CURRENT_SHELL' to '$SHELL'."
		fi
	fi
}

local_VALIDATE_INSTANCE_PERMISSIONS() {
	UPDATE="$1"
	SELECTED_INSTANCE_ID="$2"
	SELECTED_INSTANCE_PATH="$CVAR_INSTANCES_PATH/$SELECTED_INSTANCE_ID"

	if [ "$UPDATE" = "full" ]
	then
		# Change owner/group
		chown -R "$CVAR_USER:$CVAR_GROUP" "$SELECTED_INSTANCE_PATH"
		
		# Dirs and files
		find "$SELECTED_INSTANCE_PATH" -type d -exec chmod 0770 -- {} +	
		find "$SELECTED_INSTANCE_PATH" -type f -exec chmod 0660 -- {} +
	fi
	
	# Make specific files executable
	chmod 0770 "$INSTANCE_PATH/srcds_run"
	chmod 0770 "$INSTANCE_PATH/srcds_linux"
}

local_INSTANCE_IS_INSTALLED() {
	SELECTED_INSTANCE_ID="$1"
	SELECTED_INSTANCE_PATH="$CVAR_INSTANCES_PATH/$SELECTED_INSTANCE_ID"
	
	if [ -d "$SELECTED_INSTANCE_PATH" ]
	then
		if [ ! -e "$SELECTED_INSTANCE_PATH/srcds_linux" ] || [ ! -e "$SELECTED_INSTANCE_PATH/srcds_run" ]
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

# Make sure that SteamCMD is installed
func_ENSURE_STEAMCMD() {
	# We need to download SteamCMD if not done yet
	if [ ! -d "$STEAMCMD_PATH" ]
	then
		TMP_FILE_PATH="$TMP_PATH/steamcmd.archive"
	
		if ! wget -t 1 -q "$STEAMCMD_DOWNLOAD_URL" -O "$TMP_FILE_PATH"
		then
			func_EXIT_ERROR 1 "Failed to download SteamCMD from:" "  $STEAMCMD_DOWNLOAD_URL"
		else
			mkdir "$STEAMCMD_PATH"
		
			# Extract archive and overwrite server
			if tar -C "$STEAMCMD_PATH" -xzf "$TMP_FILE_PATH"
			then
				func_PRINT_INFO "Downloaded SteamCMD:" "  $STEAMCMD_PATH" ""
			fi
			
			chown -R "$CVAR_USER:$CVAR_GROUP" "$STEAMCMD_PATH"
			
			rm "$TMP_FILE_PATH"
		fi
	fi
}

func_STEAMCMD_RUNSCRIPT() {
	RUNSCRIPT_FILE_PATH="$1"
	
	setpriv --reuid="$CVAR_USER" --regid="$CVAR_GROUP" --clear-groups --reset-env -- \
	"$STEAMCMD_PATH"/steamcmd.sh +runscript "$RUNSCRIPT_FILE_PATH" >> "$LOG_PATH/steamcmd.log"
	rm "$RUNSCRIPT_FILE_PATH"
}

func_INSTALL_OR_UPDATE_GAME() {
	SERVER_APP_ID="$1"
	FULL_GAME_PATH="$2"
	
	TMP_FILE_PATH="$TMP_PATH/steamcmd.runscript.txt"
	
	printf "force_install_dir $FULL_GAME_PATH\n" > "$TMP_FILE_PATH"
	printf "login anonymous\n" >> "$TMP_FILE_PATH"
	printf "app_update $SERVER_APP_ID\n" >> "$TMP_FILE_PATH"
	printf "exit\n" >> "$TMP_FILE_PATH"
	
	if func_STEAMCMD_RUNSCRIPT "$TMP_FILE_PATH"
	then
		return 0
	fi
	
	return 1
}

local_INIT() {
	# Must not omit instance number
	if [ "$GIVEN_INSTANCE_ID" = "" ]
	then
		func_EXIT_ERROR 1 "No instance number given." "  Example: ${0} {srv[N] or [dev|live|...]}"
	fi
	
	# Validate configuration files
	if ! RESULT="$(func_ENSURE_CONFIG_VARS "$CFG_MAIN_PATH" "User Group ForcedUserShell GracefulShutdownTimeout RestartWaitTimeBetween ScreenNamePrefix InstancesPath")"
	then
		func_EXIT_ERROR 1 "$RESULT"
	fi
	
	# Create list of instances
	WAS_INSTANCE_FOUND="0"
	
	INSTANCES_LIST="$(printf '%s\n' "$CFG_INSTANCES_CONTENT" | awk '{print $1}')"
	
	for INSTANCE in $INSTANCES_LIST
	do
		if [ "$GIVEN_INSTANCE_ID" = "$INSTANCE" ]
		then
			# Don't use 'break' here, otherwise the
			# other instanced won't be checked.
			WAS_INSTANCE_FOUND="1"
		fi	
	
		# Get line for this instance in configuration file
		MATCHES="$(printf '%s\n' "$CFG_INSTANCES_CONTENT" | grep "$INSTANCE[[:space:]]" | wc -l)"
		
		# Instance ID must be unique
		if [ "$MATCHES" -gt 1 ]
		then
			func_EXIT_ERROR 1 "Instance with ID '$INSTANCE' defined twice in:" "  $CFG_INSTANCES_PATH"
		fi
		
		local_GET_AND_VALIDATE_INSTANCE_CONFIG_VARS "$INSTANCE"
	done
	
	# Validate that given instance exists
	if [ "$WAS_INSTANCE_FOUND" = "0" ]
	then
		func_PRINT_ERROR "Invalid instance id '$GIVEN_INSTANCE_ID' given. Available instances:" "$(func_INDENT_ALL_LINES "$INSTANCES_LIST")" ""
		func_EXIT_ERROR 1 "Make sure you configured the instance before installation:" "  $CFG_INSTANCES_PATH"
	fi
	
	# User/Group and shell which should be used
	CVAR_USER="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "User")"
	CVAR_GROUP="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "Group")"
	CVAR_FORCED_USER_SHELL="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "ForcedUserShell")"
	CVAR_SHUTDOWN_TIMEOUT="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "GracefulShutdownTimeout")"
	CVAR_RESTART_WAIT_TIME_BETWEEN="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "RestartWaitTimeBetween")"
	CVAR_SCREEN_NAME_PREFIX="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "ScreenNamePrefix")"
	CVAR_INSTANCES_PATH="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "InstancesPath")"
	
	if [ ! -d "$CVAR_INSTANCES_PATH" ]
	then
		func_EXIT_ERROR 1 "Directory for instances (see InstancesPath in <$(basename "$CFG_MAIN_PATH")>) does not exist:" "  $CVAR_INSTANCES_PATH"
	fi
	
	# Validate existance of user and group
	local_VALIDATE_USER_AND_GROUP "$CVAR_USER" "$CVAR_GROUP"
	
	# Force shell for user account
	local_FORCE_SHELL_FOR_USER "$CVAR_USER" "$CVAR_FORCED_USER_SHELL"

	# Make sure this process is not being executed while still running
	func_BLOCK_PROCESS "main-process" "$ABSPATH"
	
	# Install missing packages for this script
	func_CHECK_DEPENDENCIES "screen"
	
	# Debian 10 (Buster)
	if [ "$(lsb_release -sc)" = "buster" ]
	then
		DEPENDENCIES="gdb lib32gcc1 lib32ncurses5"
	# Debian 11 (Bullseye)
	elif [ "$(lsb_release -sc)" = "bullseye" ]
	then
		DEPENDENCIES="gdb lib32gcc-s1 lib32ncurses6"
	else
		func_EXIT_ERROR 1 "Unknown Linux distribution. Run 'lsb_release --all' and open an issue on GitHub:" "  https://github.com/etkaar/srcds"
	fi
	
	# Ask for installation of missing packages for SRCDS
	RESULT="$(func_CHECK_DEPENDENCIES "$DEPENDENCIES" 1)"
	CONFIRM_INSTALLATION="n"
	
	if [ ! "$RESULT" = "" ]
	then
		func_STDERR "SRCDS needs following packages: $RESULT"
		read -p "Do you want to install them now? [Y/n]: " CONFIRM_INSTALLATION
	
		if [ ! "y" = "$(printf '%s' "$CONFIRM_INSTALLATION" | tr '[:upper:]' '[:lower:]')" ]
		then
			func_EXIT_ERROR 1 "Cannot continue due to missing packages."
		else
			func_INSTALL_PACKAGES "$RESULT"
		fi
	fi
	
	# As SRCDS will look for version 5, we fix that by creating
	# a symbolic link to version 6.
	if [ "$(lsb_release -sc)" = "bullseye" ]
	then
		SYMLINK_SOURCE="/usr/lib32/libncurses.so.6"
		SYMLINK_TARGET="/usr/lib32/libncurses.so.5"
		
		if [ -e "$SYMLINK_SOURCE" ]
		then
			if [ ! -e "$SYMLINK_TARGET" ] && [ ! -L "$SYMLINK_TARGET" ]
			then
				if ln -s "$SYMLINK_SOURCE" "$SYMLINK_TARGET"
				then
					func_PRINT_INFO "Symlink created:" "  $SYMLINK_SOURCE > $SYMLINK_TARGET"
				fi
			fi
		fi
	fi
}

local_INIT

# Command
CMD="$2"

# Path of this instance
INSTANCE_PATH="$CVAR_INSTANCES_PATH/$GIVEN_INSTANCE_ID"

if [ ! -d "$INSTANCE_PATH" ]
then
	if [ ! "$CMD" = "install" ]
	then
		func_PRINT_ERROR "Directory for instance '$GIVEN_INSTANCE_ID' not found:" "  $INSTANCE_PATH" ""
		func_EXIT_ERROR 1 "Run following command to install a new instance:" "  ${0} $GIVEN_INSTANCE_ID install"
	fi
fi

# Get all configuration variables of this instance
local_GET_INSTANCE_CONFIG_VARS "$GIVEN_INSTANCE_ID"

# Commands
SCREEN_NAME="${CVAR_SCREEN_NAME_PREFIX}$GIVEN_INSTANCE_ID"
CMD_START="env RDTSC_FREQUENCY=disabled ./srcds_run -game cstrike -port $INSTANCE_PORT -ip $INSTANCE_IPV4_ADDRESS +map $INSTANCE_MAP -sv_pure -maxplayers $INSTANCE_MAX_PLAYERS -debug -steam_dir ../tools/steam -steamcmd_script ../tools/steam/steamcmd.sh -dir ."
CMD_STOP="screen -S $SCREEN_NAME -p 0 -X stuff $'\003'"

# Search string we use to find the process. So we don't need
# any PID file to check if the process is running or not.
PROCESS_SEARCH_STRING="SCREEN -L -d -m -S $SCREEN_NAME "

# Get id of the process
func_GET_INSTANCE_PID() {
	INSTANCE_PROCESS_ID="$(pgrep -f "^$PROCESS_SEARCH_STRING")"
}

func_GET_INSTANCE_PID

# Path of pid file
INSTANCE_PID_FILE="./.process.instance-$GIVEN_INSTANCE_ID.pid"

local_START() {
	# Reset permissions
	local_VALIDATE_INSTANCE_PERMISSIONS "full" "$GIVEN_INSTANCE_ID"

	# Start process
	cd "$INSTANCE_PATH" && \
	screen -L -d -m -S "$SCREEN_NAME" \
	setpriv --reuid="$CVAR_USER" --regid="$CVAR_GROUP" --clear-groups --reset-env -- $CMD_START && \
	cd "$ABSPATH"
	
	# Get id of the process
	func_GET_INSTANCE_PID
	
	# Ensure process is running
	if [ "$INSTANCE_PROCESS_ID" = "" ]
	then
		func_EXIT_ERROR 1 "Failed to start process using:" "  $CMD_START"
	else
		printf "$INSTANCE_PROCESS_ID" > "$INSTANCE_PID_FILE"
		func_PRINT_SUCCESS "Process started."
	fi
}

local_STOP() {
	rm "$INSTANCE_PID_FILE"

	# Attempt graceful shutdown in the background
	$CMD_STOP
	
	# Check periodically if process was stopped
	SECONDS_LEFT=0
	
	func_PRINT_INFO "Terminating process (pid $INSTANCE_PROCESS_ID) "
	
	while [ "$SECONDS_LEFT" -lt "$CVAR_SHUTDOWN_TIMEOUT" ]
	do
		if kill -0 "$INSTANCE_PROCESS_ID" 2>/dev/null
		then
			printf "."
			sleep 1
		else
			break
		fi
		
		SECONDS_LEFT="$(expr "$SECONDS_LEFT" + 1)"
	done

	printf "\n"
	
	# Process is still running
	if kill -0 "$INSTANCE_PROCESS_ID" 2>/dev/null
	then
		# Kill process
		kill -9 "$INSTANCE_PROCESS_ID"
		
		sleep 0.5
		
		func_EXIT_ERROR 1 "Process killed after $SECONDS_LEFT seconds."
	else
		func_PRINT_SUCCESS "Gracefully terminated."
	fi
}

case "$CMD" in
	status)
		if [ ! "$INSTANCE_PROCESS_ID" = "" ]
		then
			func_EXIT_SUCCESS "Process is running."
		else
			func_EXIT_ERROR 1 "Process not running."
		fi
	;;

	start)
		if [ ! "$INSTANCE_PROCESS_ID" = "" ]
		then
			func_EXIT_ERROR 2 "Process still running (pid $INSTANCE_PROCESS_ID)."
		else
			local_START
		fi
	;;
	
	check|cron)
		# Process not running, but it should
		if [ -e "$INSTANCE_PID_FILE" ] && [ "$INSTANCE_PROCESS_ID" = "" ]
		then
			func_STDOUT "Process not running, but it should. Trying to restart it:"
			local_START
		fi
	;;
	
	stop)
		if [ "$INSTANCE_PROCESS_ID" = "" ]
		then
			func_EXIT_ERROR 2 "Process not running."
		else
			local_STOP
		fi
	;;
	
	restart)
		if local_STOP
		then
			SECONDS_LEFT=0
			
			while [ "$SECONDS_LEFT" -lt "$CVAR_RESTART_WAIT_TIME_BETWEEN" ]
			do
				printf "."
				sleep 1
				
				SECONDS_LEFT="$(expr "$SECONDS_LEFT" + 1)"
			done
			
			printf "\n"
			
			local_START
		fi
	;;
	
	install)
		# Make sure instance is not yet installed
		if local_INSTANCE_IS_INSTALLED "$GIVEN_INSTANCE_ID"
		then
			func_EXIT_ERROR 1 "Instance '$GIVEN_INSTANCE_ID' already installed."
		else
			func_ENSURE_STEAMCMD
			
			if [ ! -d "$INSTANCE_PATH" ]
			then
				mkdir "$INSTANCE_PATH"
			fi
			
			func_PRINT_INFO "Installation of instance '$GIVEN_INSTANCE_ID' started."
			
			if func_INSTALL_OR_UPDATE_GAME "$INSTANCE_SERVER_APP_ID" "$INSTANCE_PATH"
			then
				func_EXIT_SUCCESS "Instance '$GIVEN_INSTANCE_ID' successfully installed:" "  $INSTANCE_PATH"
			fi
		fi
	;;
	
	update)
		if ! local_INSTANCE_IS_INSTALLED "$GIVEN_INSTANCE_ID"
		then
			func_EXIT_ERROR 1 "Instance '$GIVEN_INSTANCE_ID' not installed."
		else
			if [ ! "$INSTANCE_PROCESS_ID" = "" ]
			then
				func_EXIT_ERROR 1 "Cannot update instance '$GIVEN_INSTANCE_ID' while running."
			fi
		
			func_ENSURE_STEAMCMD
			
			func_PRINT_INFO "Update of instance '$GIVEN_INSTANCE_ID' started."
			
			if func_INSTALL_OR_UPDATE_GAME "$INSTANCE_SERVER_APP_ID" "$INSTANCE_PATH"
			then
				func_EXIT_SUCCESS "Instance '$GIVEN_INSTANCE_ID' successfully updated."
			fi
		fi
	;;
	
	fix-permissions)
		local_VALIDATE_INSTANCE_PERMISSIONS "full" "$GIVEN_INSTANCE_ID"
	;;
	
	*)
		func_EXIT_ERROR 1 "Usage: $APPLICATION_USE_EXAMPLE_LINE"
	;;
	
esac

func_TIDY_UP
exit 0
