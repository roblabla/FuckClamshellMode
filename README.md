# FuckClamshellMode

A macOS user-space service that monitors the MacBook lid and **locks the screen
automatically when clamshell mode is entered** (lid closed with an external
display connected).

## How it works

The service registers for `kIOPMMessageClamshellStateChange` messages through
`IOServiceAddInterestNotification` on `IOPMrootDomain` — the same technique
used by [Objective-See's DoNotDisturb](https://github.com/objective-see/DoNotDisturb/blob/master/Daemon/Monitor.m).

When the lid-close event is received **and** at least one external (non
built-in) display is active, `SACLockScreenImmediate` from the macOS private
`login` framework is called to lock the current user session immediately.

## Requirements

* macOS 12 Monterey or later
* Xcode Command Line Tools (for `swift build`)

## Build

```bash
swift build -c release
```

The compiled binary is placed at
`.build/release/FuckClamshellMode`.

## Install

1. Copy the binary to `/usr/local/bin/`:

   ```bash
   sudo cp .build/release/FuckClamshellMode /usr/local/bin/
   ```

2. Copy the LaunchAgent plist to your user agents directory and load it:

   ```bash
   cp com.roblabla.FuckClamshellMode.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/com.roblabla.FuckClamshellMode.plist
   ```

The service will now start automatically on every login. Logs are written to
`/tmp/FuckClamshellMode.log` and can also be viewed in Console.app.

## Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.roblabla.FuckClamshellMode.plist
rm ~/Library/LaunchAgents/com.roblabla.FuckClamshellMode.plist
sudo rm /usr/local/bin/FuckClamshellMode
```