# Eye Break

A gentle 20-20-20 reminder for macOS that lives in the menu bar: every 20 minutes, a small panel in the corner asks you to look about 6 m away for 20 seconds. It counts down only while you're hands-off, so it notices when you actually take the break. Starts automatically at login.

## Requirements

- macOS 14 (Sonoma) or later
- Apple's Command Line Tools, for `swiftc` (`xcode-select --install`)

## Install

```sh
./install.sh
```

Builds the app into `~/.local/bin/eye-break` and registers a LaunchAgent so it starts at every login. The 👁 icon appears in your menu bar as soon as the script finishes. Safe to re-run after changing the code.

Needs Apple's Command Line Tools (for `swiftc`). If they're missing, the script tells you to run `xcode-select --install`.

## The menu bar

The icon shows minutes until the next break (`👁 14m`). It changes to an eye with a slash when paused, a camera while a break waits for a call to end, and a filled eye while a reminder is showing.

Click it for:

- **Take a Break Now**
- **Pause for 1 Hour** / **Pause Until Tomorrow** (then **Resume**)
- Today's breaks taken and missed, and your streak
- **Open Log**
- **Quit Eye Break**: stays off until your next login. To start it again now: `launchctl kickstart gui/$(id -u)/com.tsalki.eye-break`

In Activity Monitor it shows up as `eye-break`.

## What happens at a break

1. A panel slides into the top-right: "Look away for 20s, whenever you're ready". It doesn't take focus; keep typing if you need to.
2. When you take your hands off the keyboard and mouse, it counts down. Touching anything restarts it from 20.
3. At 0, a soft chime plays and the panel fades out.
4. **Later** brings it back in 5 minutes. **Skip** waits for the next 20-minute cycle.
5. If you ignore it, it fades after 2 minutes and comes back once, 5 minutes later. Ignore that too and it waits for the next cycle. Nothing escalates.

The timer resets on its own if you lock the screen, the Mac sleeps, or you're idle for 5+ minutes. Idle time doesn't count while a video is playing (any app keeping the display awake). While the camera is on (video calls), the break waits until it's off.

### Strict mode

If you ever want it enforced, change `?? .gentle` to `?? .strict` on the `mode` line in `src/Settings.swift` and re-run `./install.sh`. Then every screen goes black until you've looked away for 20 seconds, with a 10-second warning first, one 2-minute snooze per hour, and a 2-minute give-up so you're never locked out.

## Stats

```sh
~/.local/bin/eye-break stats
```

Today's events and your streak: consecutive days with at least one break taken, and at least as many taken as missed.

## Testing with short timings

```sh
launchctl bootout gui/$(id -u)/com.tsalki.eye-break
EYE_BREAK_INTERVAL=60 EYE_BREAK_SECONDS=5 ~/.local/bin/eye-break
# Ctrl-C to stop, then ./install.sh to go back to normal
```

Only one copy runs at a time; a second one prints "Eye Break is already running." and exits.

## What it writes on your Mac

Everything stays inside your home folder. Nothing needs `sudo`, and nothing goes over the network.

| Path | Written by | What it is |
|---|---|---|
| `~/.local/bin/eye-break` | `install.sh` | The compiled app |
| `~/Library/LaunchAgents/com.tsalki.eye-break.plist` | `install.sh` | Starts the app at login, restarts it after a crash |
| `~/Library/Application Support/eye-break/` | the app | Holds `lock`, which keeps a second copy from starting |
| `~/Library/Logs/eye-break.log` | the app | Your break history; read by `eye-break stats` and the menu |
| `~/Library/Logs/eye-break.err.log` | launchd | Error output from the app; normally empty |

macOS may also list it under **System Settings → General → Login Items & Extensions → Allow in the Background**. That entry is managed by macOS and goes away once the LaunchAgent is removed.

The source folder (this repo) isn't needed at runtime; it's only used to build, reinstall and uninstall.

## Uninstall

```sh
./uninstall.sh
```

Stops the app and removes the app, the LaunchAgent and `~/Library/Application Support/eye-break/`. Your logs are kept. To remove them too:

```sh
rm ~/Library/Logs/eye-break.log ~/Library/Logs/eye-break.err.log
```

### Without the script

If you no longer have this folder, the same steps by hand:

```sh
launchctl bootout gui/$(id -u)/com.tsalki.eye-break
rm ~/Library/LaunchAgents/com.tsalki.eye-break.plist
rm ~/.local/bin/eye-break
rm -r ~/Library/Application\ Support/eye-break
rm ~/Library/Logs/eye-break.log ~/Library/Logs/eye-break.err.log   # optional: your history
```

## Another Mac

Copy this folder over (AirDrop, iCloud Drive, git) and run `./install.sh` there. The app is compiled on each Mac, so it works on both Intel and Apple Silicon.

## Source files

| File | What it is |
|---|---|
| `src/main.swift` | Entry point: runs the app, or `stats` |
| `src/Settings.swift` | All tuning: mode, interval, break length, timeouts |
| `src/Scheduler.swift` | The timer and all the rules; no UI |
| `src/MenuBar.swift` | Menu bar icon and menu; feeds the scheduler sleep, wake and lock events |
| `src/Reminders.swift` | The corner panel, and strict mode's warning and black overlay |
| `src/Checks.swift` | Idle time, lock, camera, display-held checks |
| `src/Log.swift` | Event log and stats |
| `src/com.tsalki.eye-break.plist` | LaunchAgent: start at login, restart after a crash |

## License

MIT. See [LICENSE](LICENSE).
