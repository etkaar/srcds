#!/bin/sh
: '''
Managing Script :: Source Dedicated Server (srcds)

Copyright (c) 2021-23 etkaar <https://github.com/etkaar/srcds>
Version 1.0.2 (January, 23th 2023)

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
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Change working directory
ABSPATH="$(cd "$(dirname "$0")"; pwd -P)"
cd "$ABSPATH"

# Paths
APP_PATH="$ABSPATH/app"
CONF_PATH="$ABSPATH/conf"
LOG_PATH="$ABSPATH/log"
CACHE_PATH="$ABSPATH/.cache"
TMP_PATH="$ABSPATH/.tmp"

# Import functions
. ./inc/generic.sh
. ./inc/instances.sh
. ./inc/steamcmd.sh

if [ ! "$(whoami)" = "root" ]
then
	func_EXIT_ERROR 1 "You need to run this command as root."
fi

# Use example for this application
APPLICATION_USE_EXAMPLE_LINE="USAGE
  ${0} [screen] [<Instance-ID>]
  ${0} [status|start|stop|restart|check|install|update] [all|<Instance-ID>]"

local_INIT() {
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
			func_EXIT_ERROR 1 "Can't continue due to missing packages."
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
COMMAND="$1"
GIVEN_INSTANCE_ID="$2"

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
CFG_GAMES_PATH="$CONF_PATH/games.txt"

CFG_INSTANCES_CONTENT="$(func_READ_CONFIG_FILE "$CFG_INSTANCES_PATH")"
CFG_GAMES_CONTENT="$(func_READ_CONFIG_FILE "$CFG_GAMES_PATH")"

# Validate presence of configuration files
for CHECKFILE in "$CFG_MAIN_PATH" "$CFG_INSTANCES_PATH"
do
	if [ ! -e "$CHECKFILE" ]
	then
		func_EXIT_ERROR 1 "Configuration file not present:" "  $CHECKFILE"
	fi
done

# Default permissions for directories owned by <User:Group> (see main.conf)
DEFAULT_DIR_PERMISSIONS=770
DEFAULT_FILE_PERMISSIONS=660

# Configuration
CVAR_USER="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "User")"
CVAR_GROUP="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "Group")"
CVAR_FORCED_USER_SHELL="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "ForcedUserShell")"
CVAR_SHUTDOWN_TIMEOUT="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "GracefulShutdownTimeout")"
CVAR_RESTART_WAIT_TIME_BETWEEN="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "RestartWaitTimeBetween")"
CVAR_SCREEN_NAME_PREFIX="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "ScreenNamePrefix")"
CVAR_INSTANCES_PATH="$(func_READ_FROM_CONFIG "$CFG_MAIN_PATH" "InstancesPath")"

# Validate configuration files
if ! RESULT="$(func_ENSURE_CONFIG_VARS "$CFG_MAIN_PATH" "User Group ForcedUserShell GracefulShutdownTimeout RestartWaitTimeBetween ScreenNamePrefix InstancesPath")"
then
	func_EXIT_ERROR 1 "$RESULT"
fi

# Create instances directoy if not exists
if [ ! -e "$CVAR_INSTANCES_PATH" ]
then
	if mkdir -p "$CVAR_INSTANCES_PATH"
	then
		func_PRINT_INFO "Directory for instances created:" "  $CVAR_INSTANCES_PATH"
	fi
fi

# Validate ownership and permissions.
# NOTE: This is mandatory, because SteamCMD tends to silently
# fail if permissions are not correct.
if ! func_VALIDATE_OWNERSHIP "$CVAR_INSTANCES_PATH" "$CVAR_USER" "$CVAR_GROUP"
then
	func_PRINT_INFO "Ownership for $CVAR_INSTANCES_PATH changed to:" "  $CVAR_USER:$CVAR_GROUP"
fi

if ! func_VALIDATE_PERMISSIONS "$CVAR_INSTANCES_PATH" "$DEFAULT_DIR_PERMISSIONS"
then
	func_PRINT_INFO "Permissions for $CVAR_INSTANCES_PATH changed to:" "  $DEFAULT_DIR_PERMISSIONS"
fi

# Ensure user exists
if ! func_USER_EXISTS "$CVAR_USER"
then
	func_EXIT_ERROR 1 "User '$CVAR_USER' does not exist."
fi

if [ "$CVAR_GROUP" = "" ]
then
	CVAR_GROUP="$CVAR_USER"
fi

# Ensure group exists
if ! func_GROUP_EXISTS "$CVAR_GROUP"
then
	func_EXIT_ERROR 1 "Group '$CVAR_GROUP' does not exist."
fi

# Force shell for user account
if ! func_FORCE_SHELL_FOR_USER "$CVAR_USER" "$CVAR_FORCED_USER_SHELL"
then
	func_PRINT_INFO "Changed shell for user '$USER' from '$CURRENT_SHELL' to '$SHELL'."
fi

# Use either all instances or only the given one
if [ "$GIVEN_INSTANCE_ID" = "all" ]
then
	GIVEN_INSTANCE_LIST="$(instance_GET_LIST)"
	MULTIPLE_INSTANCES=1
else
	GIVEN_INSTANCE_LIST="$(printf '%s' "$GIVEN_INSTANCE_ID" | tr ',' "\n")"
	
	if [ "$(printf "$GIVEN_INSTANCE_LIST" | wc -l)" -gt 0 ]
	then
		MULTIPLE_INSTANCES=1
	else
		MULTIPLE_INSTANCES=0
	fi
fi

# Cannot reattach screen for multiple instances
if [ "$MULTIPLE_INSTANCES" -eq 1 ] && [ "$COMMAND" = "screen" ]
then
	func_PRINT_ERROR "Command '$COMMAND' does not support multiple instances."
	func_EXIT_ERROR 1 "$APPLICATION_USE_EXAMPLE_LINE"
fi

# Command 'cron' will only invoke 'check all', so we can omit these checks
if [ ! "$COMMAND" = "cron" ]
then
	# Must not omit instance id
	if [ "$GIVEN_INSTANCE_ID" = "" ]
	then
		func_PRINT_ERROR "No instance id given."
		func_EXIT_ERROR 1 "$APPLICATION_USE_EXAMPLE_LINE"
	fi
	
	# Create list of instances
	WAS_INSTANCE_FOUND="0"
	INSTANCES_LIST="$(instance_GET_LIST)"
	
	# These checks are always performed because we want to make
	# sure that the whole configuration file is valid.
	for INSTANCE in $INSTANCES_LIST
	do
		# Only if a specific instance was given
		if [ "$MULTIPLE_INSTANCES" -eq 0 ]
		then
			if [ "$GIVEN_INSTANCE_ID" = "$INSTANCE" ]
			then
				# Don't use 'break' here, otherwise the
				# other instance won't be checked.
				WAS_INSTANCE_FOUND="1"
			fi
		fi
		
		# Get line for this instance in configuration file
		MATCHES="$(printf '%s\n' "$CFG_INSTANCES_CONTENT" | grep "^$INSTANCE[[:space:]]" | wc -l)"
		
		# Instance id must be unique
		if [ "$MATCHES" -gt 1 ]
		then
			func_EXIT_ERROR 1 "Instance <$INSTANCE> defined twice in:" "  $CFG_INSTANCES_PATH"
		fi
		
		instance_GET_AND_VALIDATE_CONFIG_VARS "$INSTANCE"
	done
	
	# Only if a specific instance was given
	if [ "$MULTIPLE_INSTANCES" -eq 0 ]
	then
		# Validate that given instance exists
		if [ "$WAS_INSTANCE_FOUND" = "0" ]
		then
			func_PRINT_ERROR "Invalid instance '$GIVEN_INSTANCE_ID' given. Available instances:" "$(func_INDENT_ALL_LINES "$INSTANCES_LIST")" ""
			func_EXIT_ERROR 1 "Make sure you configured the instance before installation:" "  $CFG_INSTANCES_PATH"
		fi
	fi
fi

local_START() {
	SELECTED_INSTANCE_ID="$1"
	
	# Get instance vars (such as the screen name)
	instance_GET_INSTANCE_VARS "$SELECTED_INSTANCE_ID"
	
	# Reset permissions
	instance_VALIDATE_PERMISSIONS "full" "$SELECTED_INSTANCE_ID"

	# Start process
	cd "$INSTANCE_PATH" && \
	screen -L -d -m -S "$SCREEN_NAME" \
	setpriv --reuid="$CVAR_USER" --regid="$CVAR_GROUP" --clear-groups --reset-env -- $CMD_START && \
	cd "$ABSPATH"
	
	# Get main process id
	instance_GET_MAIN_PID
	
	# Ensure process is running
	if [ "$INSTANCE_MAIN_PROCESS_ID" = "" ]
	then
		func_EXIT_ERROR 2 "Failed to start process using:" "  $CMD_START"
	else
		printf "$INSTANCE_MAIN_PROCESS_ID" > "$INSTANCE_MAIN_PID_FILE"
		
		# It can happen that the sub process is not immediately spawned,
		# so we need to wait for it being ready.
		TIMEOUT=50
		SECONDS_LEFT=0
		
		func_PRINT_INFO "Wait for sub process: "
		
		while true
		do
			if [ "$SECONDS_LEFT" -gt "$TIMEOUT" ]
			then
				func_PRINT_ERROR "Can't find sub process, therefore terminating main process:"
				func_EXIT_ERROR 2 "$(local_STOP "$SELECTED_INSTANCE_ID")"
			else
				instance_GET_SUB_PID
				
				if [ "$INSTANCE_SUB_PROCESS_ID" = "" ]
				then
					printf "."
					sleep 0.1
				else
					break
				fi
				
				SECONDS_LEFT="$(expr "$SECONDS_LEFT" + 1)"
			fi
		done
		
		if [ "$SECONDS_LEFT" -gt 0 ]
		then
			printf "\n"
		fi
		
		func_PRINT_SUCCESS "Instance <$SELECTED_INSTANCE_ID> started with following command:" "  $CMD_START"
	fi
	
	# Bind process to specific CPU cores
	if [ ! "$INSTANCE_CPU_CORES" = "default" ]
	then
		if taskset --all-tasks --cpu-list --pid "$INSTANCE_CPU_CORES" "$INSTANCE_SUB_PROCESS_ID" 1>/dev/null
		then
			func_PRINT_INFO "PID $INSTANCE_SUB_PROCESS_ID: Bound to CPU cores $INSTANCE_CPU_CORES."
		fi
	fi
	
	# Change priority to real-time (SCHED_RR, sched_priority 1)
	if [ "$INSTANCE_PRIORITY" = "real-time" ]
	then
		if chrt --rr -p 1 "$INSTANCE_SUB_PROCESS_ID"
		then
			func_PRINT_INFO "PID $INSTANCE_SUB_PROCESS_ID: Applied real-time priority SCHED_RR."
		fi
	fi
}

local_STOP() {
	SELECTED_INSTANCE_ID="$1"
	
	# Get instance vars (such as the screen name)
	instance_GET_INSTANCE_VARS "$SELECTED_INSTANCE_ID"
	
	# Get main process id
	instance_GET_MAIN_PID	
	
	# Delete old pid file
	rm "$INSTANCE_MAIN_PID_FILE"

	# Attempt graceful shutdown in the background
	$CMD_STOP
	
	func_PRINT_INFO "Stopping instance <$SELECTED_INSTANCE_ID> (pid $INSTANCE_MAIN_PROCESS_ID): "
	
	if ! func_WAIT_FOR_TERMINATION "$INSTANCE_MAIN_PROCESS_ID" "$CVAR_SHUTDOWN_TIMEOUT"
	then
		printf "\n"
		
		# Kill process
		kill -9 "$INSTANCE_MAIN_PROCESS_ID"
		sleep 0.5
		
		func_EXIT_ERROR 2 "Process killed due to timeout."
	else
		printf "\n"
		func_PRINT_SUCCESS "Instance stopped." 
	fi
}

case "$COMMAND" in
	status)
		EXIT_CODE=0
		
		for INSTANCE in $GIVEN_INSTANCE_LIST
		do
			if ! instance_IS_INSTALLED "$INSTANCE"
			then
				func_PRINT_INFO "Instance <$INSTANCE>: Not installed"
			else
				if instance_IS_RUNNING "$INSTANCE"
				then
					func_PRINT_SUCCESS "Instance <$INSTANCE>: Running" "  $INSTANCE_GAME_SHORTNAME ($INSTANCE_SERVER_APP_ID)" "    $INSTANCE_IPV4_ADDRESS:$INSTANCE_PORT"
					
				else
					func_PRINT_WARNING "Instance <$INSTANCE>: Stopped"
					EXIT_CODE=1
				fi
			fi
		done
		
		func_EXIT "$EXIT_CODE"
	;;

	start)
		EXIT_CODE=0
		
		for INSTANCE in $GIVEN_INSTANCE_LIST
		do
			if ! instance_IS_INSTALLED "$INSTANCE"
			then
				if [ "$MULTIPLE_INSTANCES" -eq 0 ]
				then
					func_PRINT_WARNING "Can't start instance <$INSTANCE>: Not installed"
					EXIT_CODE=1
				fi
			else
				if instance_IS_RUNNING "$INSTANCE"
				then
					if [ "$MULTIPLE_INSTANCES" -eq 0 ]
					then
						func_PRINT_WARNING "Can't start instance <$INSTANCE>: Already running (pid $INSTANCE_MAIN_PROCESS_ID)"
						EXIT_CODE=1
					fi
				else
					local_START "$INSTANCE"
				fi
			fi
		done
		
		func_EXIT "$EXIT_CODE"
	;;

	stop)
		EXIT_CODE=0
		
		for INSTANCE in $GIVEN_INSTANCE_LIST
		do
			if ! instance_IS_INSTALLED "$INSTANCE"
			then
				if [ "$MULTIPLE_INSTANCES" -eq 0 ]
				then
					func_PRINT_WARNING "Can't stop instance <$INSTANCE>: Not installed"
					EXIT_CODE=1
				fi
			else
				if ! instance_IS_RUNNING "$INSTANCE"
				then
					if [ "$MULTIPLE_INSTANCES" -eq 0 ]
					then
						func_PRINT_WARNING "Can't stop instance <$INSTANCE>: Not running"
						EXIT_CODE=1
					fi
				else
					local_STOP "$INSTANCE"
				fi
			fi
		done
		
		func_EXIT "$EXIT_CODE"
	;;
	
	restart)
		EXIT_CODE=0
		
		for INSTANCE in $GIVEN_INSTANCE_LIST
		do
			if ! instance_IS_INSTALLED "$INSTANCE"
			then
				if [ "$MULTIPLE_INSTANCES" -eq 0 ]
				then
					func_PRINT_WARNING "Can't restart instance <$INSTANCE>: Not installed"
					EXIT_CODE=1
				fi
			else
				if ! instance_IS_RUNNING "$INSTANCE"
				then
					if [ "$MULTIPLE_INSTANCES" -eq 0 ]
					then
						func_PRINT_WARNING "Can't restart instance <$INSTANCE>: Not running"
						EXIT_CODE=1
					fi
				else
					if local_STOP "$INSTANCE"
					then
						TIMEOUT="$(expr "$CVAR_RESTART_WAIT_TIME_BETWEEN" \* 10)"
						SECONDS_LEFT=0
						
						func_PRINT_INFO "Wait $CVAR_RESTART_WAIT_TIME_BETWEEN seconds: "
						
						while [ "$SECONDS_LEFT" -lt "$TIMEOUT" ]
						do
							printf "."
							sleep 0.1
							
							SECONDS_LEFT="$(expr "$SECONDS_LEFT" + 1)"
						done
						
						printf "\n"
						
						local_START "$INSTANCE"
					fi
				fi
			fi
		done
		
		func_EXIT "$EXIT_CODE"
	;;
	
	install)
		EXIT_CODE=0

		for INSTANCE in $GIVEN_INSTANCE_LIST
		do
			if instance_IS_INSTALLED "$INSTANCE"
			then
				if [ "$MULTIPLE_INSTANCES" -eq 0 ]
				then
					func_PRINT_WARNING "Can't install instance <$INSTANCE>: Already installed"
					EXIT_CODE=1
				fi
			else
				steamcmd_ENSURE
				
				if [ ! -d "$INSTANCE_PATH" ]
				then
					mkdir "$INSTANCE_PATH"
					
					chmod "$DEFAULT_DIR_PERMISSIONS" "$INSTANCE_PATH"
					chown "$CVAR_USER:$CVAR_GROUP" "$INSTANCE_PATH"
				fi
				
				func_PRINT_INFO "Installation of instance <$INSTANCE> started."
				
				if steamcmd_INSTALL_OR_UPDATE_GAME "$INSTANCE_SERVER_APP_ID" "$INSTANCE_PATH"
				then
					func_PRINT_SUCCESS "Completed:" "  $INSTANCE_PATH"
				fi
			fi
		done
		
		func_EXIT "$EXIT_CODE"
	;;
	
	update)
		EXIT_CODE=0

		for INSTANCE in $GIVEN_INSTANCE_LIST
		do
			if ! instance_IS_INSTALLED "$INSTANCE"
			then
				if [ "$MULTIPLE_INSTANCES" -eq 0 ]
				then
					func_PRINT_WARNING "Can't update instance <$INSTANCE>: Not installed"
					EXIT_CODE=1
				fi
			else
				if instance_IS_RUNNING "$INSTANCE"
				then
					if [ "$MULTIPLE_INSTANCES" -eq 0 ]
					then
						func_EXIT_WARNING 1 "Can't update instance <$INSTANCE>: Still running"
					fi
				else
					steamcmd_ENSURE
					
					func_PRINT_INFO "Update of instance '$GIVEN_INSTANCE_ID' started."
					
					if steamcmd_INSTALL_OR_UPDATE_GAME "$INSTANCE_SERVER_APP_ID" "$INSTANCE_PATH" "1"
					then
						func_PRINT_SUCCESS "Completed:" "  $INSTANCE_PATH"
					fi
				fi
			fi
		done
		
		func_EXIT "$EXIT_CODE"
	;;
	
	check)		
		for INSTANCE in $GIVEN_INSTANCE_LIST
		do
			if instance_IS_INSTALLED "$INSTANCE"
			then
				if [ "$INSTANCE_STATUS" = "always-online" ]
				then
					if ! instance_IS_RUNNING "$INSTANCE"
					then
						local_START "$INSTANCE"
						printf "\n"
					fi
				fi
			fi
		done
	;;
	
	screen)
		if ! instance_IS_INSTALLED "$GIVEN_INSTANCE_ID"
		then
			func_EXIT_WARNING 1 "Can't reattach screen <$SCREEN_NAME>: Instance <$GIVEN_INSTANCE_ID> not installed"
		else
			if ! instance_IS_RUNNING "$GIVEN_INSTANCE_ID"
			then
				func_EXIT_WARNING 1 "Can't reattach screen <$SCREEN_NAME>: Instance <$GIVEN_INSTANCE_ID> not running"
			else
				screen -r "$SCREEN_NAME"
			fi
		fi
	;;
	
	cron)
		func_TIDY_UP
		
		${0} check all
	;;
	
	validate-permissions)
		for INSTANCE in $GIVEN_INSTANCE_LIST
		do
			if ! instance_IS_INSTALLED "$INSTANCE"
			then
				if [ "$MULTIPLE_INSTANCES" -eq 0 ]
				then
					func_PRINT_WARNING "Can't validate permissions for instance <$INSTANCE>: Not installed"
					EXIT_CODE=1
				fi
			else
				instance_VALIDATE_PERMISSIONS "full" "$INSTANCE"
			fi
		done
	;;
	
	*)
		func_EXIT_WARNING 1 "$APPLICATION_USE_EXAMPLE_LINE"
	;;
	
esac

func_TIDY_UP
exit 0
