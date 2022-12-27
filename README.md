# SRCDS
Script to manage one or multiple instances of Source Dedicated Servers (SRCDS), such as CS:GO or TF2. Written in Dash ([Debian Almquist Shell](https://wiki.archlinux.org/title/Dash)) to offer POSIX compliance.

## 1.0 Notes

This script was tested on Debian 11 Bullseye. It already works, but some features are not available yet.

---

## 2.0 Installation

In the following examples, we will use `/home/gameserver/srcds` as script path and `/home/gameserver/srcds/instances` (you can change that in `conf/main.conf`) for the gameservers. Thus, login with `root` permissions, manually download the code and move its content there:

```shell
mkdir /home/gameserver/srcds
cd /home/gameserver/srcds
wget https://github.com/etkaar/srcds/archive/refs/heads/main.tar.gz
tar -xzf main.tar.gz --strip-components=1
rm main.tar.gz
```

Create a lower privileged user:

```
useradd gameserver --no-create-home --home-dir /home/gameserver --shell /usr/sbin/nologin
```

---

## 3.0 Security

Gameservers are running within a screen session. This makes it possible to both read from and write to the gameserver console.

In order to make them available for easy reattachments by root (`screen -r`) or another higher privileged user, these screens are started by this very user. However, privileges are still always dropped for the actual gameserver process, which is started by a lower privileged user (see `conf/main.conf`) without shell access:

```shell
cd "$INSTANCE_PATH" && \
screen -L -d -m -S "$SCREEN_NAME" \
setpriv --reuid="$CVAR_USER" --regid="$CVAR_GROUP" --clear-groups --reset-env -- $CMD_START && \
cd "$ABSPATH"
```

---

## 4.0 Configuration

### conf/main.conf

```shell
# You usually want to use a lower privileged user
# account to run the server. Don't use root.
User gameserver
Group gameserver
ForcedUserShell /usr/sbin/nologin

# Time granted for a graceful shutdown (after that,
# process is going to be killed)
GracefulShutdownTimeout 10

# Wait time between stop and restart
RestartWaitTimeBetween 5

# Prefix for the screen name (prefix-{INSTANCE-ID})
ScreenNamePrefix "srcds-"

# Instances are stored into this directory,
# e.g. /home/gameserver/srcds/instances/srv01 for an instance with id 'srv01'
InstancesPath /home/gameserver/srcds/instances

# Multiple instances are possible,
# see <conf/instances.conf>.
```

### conf/instances.conf

```shell
# Instance ID       Server App ID[1]     IPv4 Address          Port        Map             Max. Players     Status[2]          Priority
example             232330               127.0.0.1             27015       cs_office       64               always-online      default

# [1] Server App IDs
#   232330 (Counter-Strike: Source)
#   232290 (Day of Defeat: Source)
#   232250 (Team Fortress 2)
#   ...
#
# See 'Linux Dedicated Server' in
# https://developer.valvesoftware.com/wiki/Dedicated_Servers_List

# [2] Status
#   always-online: Gameserver is always restarted (gameserver crash, restart of the dedicated server, ...).
```

---

## 5.0 Commands

**5.1 Status**

Find out if an instance is currently running or not:

```shell
/home/gameserver/srcds/app.sh example status
```

**5.2 Install Instance**

Install instance (*= gameserver*), which was previously defined in `conf/instances.conf`:

```shell
/home/gameserver/srcds/app.sh example install
```

**5.3 Install Instance**

Update instance:

```shell
/home/gameserver/srcds/app.sh example update
```

**5.4 Start Instance**

```shell
/home/gameserver/srcds/app.sh example start
```

**5.5 Stop Instance**

```shell
/home/gameserver/srcds/app.sh example stop
```
