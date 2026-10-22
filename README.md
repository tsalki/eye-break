# Eye Break

A gentle reminder for macOS that lives in the menu bar and follows the 20-20-20 rule: every 20 minutes, look at something 20 feet (about 6 m) away for 20 seconds. A small panel at the top of the screen asks you to. It counts down only while you're hands-off, so it notices when you actually take the break. Starts automatically at login.

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
- **Settings**: how often to take a break (20 to 60 minutes) and how long it lasts (10 to 60 seconds). Your choice is saved and kept across restarts. Changing how often restarts the countdown.
- Today's breaks taken and missed, and your streak
- **Open Log**
- **Quit Eye Break**: stays off until your next login. To start it again now: `launchctl kickstart gui/$(id -u)/com.tsalki.eye-break`

In Activity Monitor it shows up as `eye-break`.

## What happens at a break

1. A small panel fades in at the top center: "Your eyes could use some distance and a few blinks". It doesn't take focus; keep typing if you need to.
2. When you take your hands off the keyboard and mouse, it counts down under the motto «Νοῦς ὑγιὴς ἐν σώματι ὑγιεῖ», ancient Greek for "a healthy mind in a healthy body". Touching anything restarts it.
3. At 0, a soft chime plays and the panel fades out.
4. **Skip** skips this break and restarts the countdown.
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
| `~/Library/Preferences/com.tsalki.eye-break.plist` | the app | Your choices from the Settings menu |
| `~/Library/Logs/eye-break.log` | the app | Your break history; read by `eye-break stats` and the menu |
| `~/Library/Logs/eye-break.err.log` | launchd | Error output from the app; normally empty |

macOS may also list it under **System Settings → General → Login Items & Extensions → Allow in the Background**. That entry is managed by macOS and goes away once the LaunchAgent is removed.

The source folder (this repo) isn't needed at runtime; it's only used to build, reinstall and uninstall.

## Uninstall

```sh
./uninstall.sh
```

Stops the app and removes the app, the LaunchAgent, your settings and `~/Library/Application Support/eye-break/`. Your logs are kept. To remove them too:

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
defaults delete com.tsalki.eye-break
rm ~/Library/Logs/eye-break.log ~/Library/Logs/eye-break.err.log   # optional: your history
```

## License

MIT. See [LICENSE](LICENSE).
