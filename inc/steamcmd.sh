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

STEAMCMD_PATH="$CACHE_PATH/steamcmd"
STEAMCMD_DOWNLOAD_URL="https://media.steampowered.com/client/steamcmd_linux.tar.gz"

STEAMCMD_LOG_FILE="$LOG_PATH/steamcmd.log"

# Make sure that SteamCMD is installed
steamcmd_ENSURE() {
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

steamcmd_RUNSCRIPT() {
	RUNSCRIPT_FILE_PATH="$1"
	
	setpriv --reuid="$CVAR_USER" --regid="$CVAR_GROUP" --clear-groups --reset-env -- \
	"$STEAMCMD_PATH"/steamcmd.sh +runscript "$RUNSCRIPT_FILE_PATH" >> "$STEAMCMD_LOG_FILE"
	rm "$RUNSCRIPT_FILE_PATH"
}

steamcmd_INSTALL_OR_UPDATE_GAME() {
	SERVER_APP_ID="$1"
	FULL_GAME_PATH="$2"
	VALIDATE="$3"
	
	TMP_FILE_PATH="$TMP_PATH/steamcmd.runscript.txt"
	
	printf "force_install_dir $FULL_GAME_PATH\n" > "$TMP_FILE_PATH"
	printf "login anonymous\n" >> "$TMP_FILE_PATH"
	
	if [ "$VALIDATE" = "1" ]
	then
		printf "app_update $SERVER_APP_ID validate\n" >> "$TMP_FILE_PATH"
	else
		printf "app_update $SERVER_APP_ID\n" >> "$TMP_FILE_PATH"
	fi
	
	printf "exit\n" >> "$TMP_FILE_PATH"
	
	if steamcmd_RUNSCRIPT "$TMP_FILE_PATH"
	then
		# Must not be empty after installation
		if [ "$(ls -A "$FULL_GAME_PATH")" = "" ]
		then
			func_EXIT_ERROR 1 "SteamCMD has failed for unknown reason, please see:" "  $STEAMCMD_LOG_FILE"
		fi
		
		return 0
	fi
	
	return 1
}
