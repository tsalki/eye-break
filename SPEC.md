# Eye Break — Design

This document describes how Eye Break behaves and why. For installing and using it, see [README.md](README.md).

## 1. Overview

Eye Break is a macOS menu bar app that reminds you to follow the **20-20-20 rule**: every 20 minutes of screen use, look at something about 20 feet (6 m) away for 20 seconds.

It tries to notice whether a break actually happened, using keyboard and mouse inactivity, and to stay out of the way when a reminder would be unwelcome.

## 2. Goals and non-goals

**Goals**

- Breaks happen without having to remember them.
- Never get in the way of important work: by default the reminder is a suggestion, not a lock.
- Notice whether a break actually happened.
- Don't interrupt at the wrong moment: locked screen, sleep, video calls.
- Visible at a glance in the menu bar; easy to pause.
- Start at login, survive crashes, and be easy to remove completely.

**Non-goals**

- Medical advice. The 20-20-20 rule is a common guideline for reducing eye strain; Eye Break just reminds you of it.
- Knowing where you're looking. Eye Break never uses the camera image, so it can't tell reading from looking away (see [§8](#8-known-limitations)).
- Accounts, sync, telemetry, or anything that needs the network.
- App Store distribution. It's built from source on each Mac.

## 3. Privacy

- **No network access.** Nothing is sent anywhere.
- **No permission prompts.** Every check uses APIs that macOS allows without asking.
- **What it reads:** seconds since the last keyboard/mouse input, whether the screen is locked, whether *any* camera is in use (an on/off flag, never the video), and which processes hold "keep the display awake" power assertions.
- **What it writes:** a local event log in `~/Library/Logs/eye-break.log`. Nothing else leaves your home folder. The full list of paths is in the README.

## 4. Compatibility

- macOS 14 (Sonoma) or later.
- Apple Silicon and Intel: `install.sh` compiles for the Mac it runs on.
- Requires Apple's Command Line Tools for `swiftc`. No Xcode project and no third-party dependencies.

## 5. Architecture

One Swift app with no Dock icon, started at login by a per-user LaunchAgent.

```
login ──► LaunchAgent (RunAtLoad, KeepAlive on crash only)
              │
              ▼
         eye-break  (menu bar app)
           MenuBar ── 5 s timer, sleep/wake/lock notifications ──► Scheduler
                                                                     │ Probe: idle, locked, camera, display held
                                                                     │ present(kind) → Outcome
                                                                     ▼
                                                                  Reminders: Nudge · Warning · Overlay
```

| File | Role |
|---|---|
| `src/main.swift` | Entry point: `eye-break` runs the app, `eye-break stats` prints stats. Single-instance lock via `flock` |
| `src/Settings.swift` | All tuning constants, with environment-variable overrides for testing |
| `src/Scheduler.swift` | The timer and every rule in this document. No UI code |
| `src/MenuBar.swift` | Status item and menu; owns the Scheduler and forwards ticks and system events to it |
| `src/Reminders.swift` | On-screen reminders: Nudge (gentle mode), Warning and Overlay (strict mode) |
| `src/Checks.swift` | System probes: idle time, lock state, camera in use, display held awake |
| `src/Log.swift` | Event log, today's counts and streak |
| `src/com.tsalki.eye-break.plist` | LaunchAgent template; `install.sh` fills in the paths |

**Why the Scheduler has no UI:** system state comes in through a `Probe` (a struct of closures), the current time through a `now` closure, and reminders go out through a `present` closure that returns an `Outcome` later. This keeps all the rules in one place and lets them be driven by a fake clock, fake probes and a fake presenter, without anything appearing on screen.

## 6. Behavior

### 6.1 Timer

Checked every 5 seconds, in this order:

1. **Paused?** Do nothing until the pause ends, then restart the timer.
2. **Screen locked** counts as a break and restarts the timer, even with the camera on.
3. **Camera on:** you're on a call, so you're not away. If a break is due, it waits until the camera is off and logs `skipped camera` once.
4. **Idle ≥ 5 minutes** counts as a break and restarts the timer, unless an app is keeping the display awake (video players and call apps do). Short idle doesn't count, since reading produces no input.
5. **Break due** → show a reminder.

System events are handled as they arrive:

- **Sleep:** any reminder on screen is taken down. On wake, one `natural sleep` is logged and the timer restarts. A reminder that a tick put up just before the wake notification is taken down too.
- **Lock** (`com.apple.screenIsLocked`): any reminder is taken down, `natural locked` is logged, and the timer restarts.
- Each absence is logged once, however it's detected.

The two more expensive probes only run when they matter: the camera check only when a break is due or idle ≥ 5 min, and the display-held check only when idle ≥ 5 min.

**Display held awake** means a process holds a `PreventUserIdleDisplaySleep` power assertion. Holders that don't mean someone is watching are ignored: `UniversalControl`, `caffeinate` and `powerd`.

### 6.2 Gentle mode (default)

1. A non-activating panel appears in the top-right: "Look away for 20s, whenever you're ready", with **Later** and **Skip** buttons. It never takes keyboard focus.
2. The countdown runs only while there's no keyboard or mouse input, counting from when the panel appeared. Any input restarts it. The panel shows "Looking away… N".
3. At zero, the "Glass" sound plays, the panel fades out, and `taken` is logged.
4. **Later** brings it back in 5 minutes. **Skip** waits a full cycle.
5. If it's **ignored** for 2 minutes, it fades and comes back once after 5 minutes. If that one is ignored too, it waits a full cycle. It never escalates.

### 6.3 Strict mode

Enabled by changing the default `mode` in `src/Settings.swift` to `.strict`, or with `EYE_BREAK_MODE=strict`.

1. A 10-second warning panel appears, with **Snooze 2 min** (allowed once per rolling hour).
2. Then a black window covers every screen, above everything else. The cursor is hidden and keystrokes are swallowed. It shows the countdown and "Look at something about 6 m away".
3. Any input restarts the 20 seconds (after a 1.5-second grace period) and plays "Tink". "Glass" plays when it's done, and focus returns to the app you were using.
4. **Escape hatch:** after 2 minutes without completing, the overlay closes and `abandoned` is logged. You can never be locked out.
5. **Take a Break Now** skips the warning.

### 6.4 Menu bar

- **Icon:** `eye` with minutes left (`14m`). It changes to `eye.slash` when paused, `video` while a due break waits for the camera, and `eye.fill` while a reminder is showing.
- **Menu:** a status line, Take a Break Now (disabled while one is showing), Pause for 1 Hour and Pause Until Tomorrow (or Resume), today's taken/missed counts and streak, Open Log, and Quit.
- **Pausing** takes down any reminder. While paused, sleep and lock aren't logged. The pause ends on its own.
- **Quit** exits cleanly, and the LaunchAgent only restarts the app after a crash (`KeepAlive` → `SuccessfulExit: false`), so it stays off until the next login.

## 7. Log and stats

`~/Library/Logs/eye-break.log` is tab-separated, one line per event: timestamp, event, detail.

```
2026-10-18T14:00:00	start	gentle
2026-10-18T14:20:03	taken	26s
2026-10-18T14:41:10	natural	away
2026-10-18T15:01:12	skipped	camera
2026-10-18T15:21:30	later	-
2026-10-18T15:28:31	missed	retrying
2026-10-18T15:35:31	missed	-
2026-10-18T15:55:40	skipped	user
2026-10-18T16:00:00	paused	1h
2026-10-18T17:00:00	resumed	-
2026-10-18T19:00:00	quit	-
```

| Event | Detail | Meaning |
|---|---|---|
| `start` | mode | The app started |
| `taken` | duration | A break was completed |
| `natural` | `away`, `sleep`, `locked` | You were away, which counts as a break |
| `skipped` | `camera` | A due break waited for a call |
| `skipped` | `user` | You clicked Skip |
| `later` | – | You clicked Later |
| `missed` | `retrying` | A reminder was ignored and will come back |
| `missed` | – | A reminder was ignored twice |
| `paused` / `resumed` | `1h`, `tomorrow` / – | Pause from the menu, and its end |
| `snoozed` | – | Strict mode: snooze clicked |
| `abandoned` | duration | Strict mode: the overlay gave up |
| `quit` | – | Quit from the menu |

**Streak:** consecutive days with at least one `taken` break, and at least as many taken as missed. Misses are `skipped user`, a final `missed`, and `abandoned`. Camera holds and `missed retrying` don't count against you. Today doesn't break the streak until it becomes a bad day. Today's counts also leave out `missed retrying`.

## 8. Known limitations

- **Hands-off isn't the same as looking away.** If you sit still reading, or watch a video without touching anything, the reminder counts it as a break. Telling these apart would need the camera image, which is out of scope.
- **Keep-awake utilities** such as Amphetamine or KeepingYouAwake hold the display awake permanently, so being idle never counts as away while they run. Add them to `ignoredDisplayHolders` in `src/Checks.swift`.
- **Older video players** that use the legacy `NoDisplaySleepAssertion` type aren't recognised as keeping the display awake.
- **Any app using the camera** holds breaks, not just call apps.
- **Focus modes** aren't detected. Detecting the active Focus needs Full Disk Access and an undocumented file.
- **Strict-mode snooze allowance** is kept in memory and resets when the app restarts.
- **The reminder panel** appears on the main screen only.

## 9. Configuration

All settings are constants in `src/Settings.swift`. Edit them, then re-run `./install.sh`.

| Setting | Default | Environment override |
|---|---|---|
| `mode` | `.gentle` | `EYE_BREAK_MODE` (`gentle` / `strict`) |
| `interval` | 20 min | `EYE_BREAK_INTERVAL` (seconds) |
| `breakLength` | 20 s | `EYE_BREAK_SECONDS` |
| `away` | 5 min | – |
| `tick` | 5 s | – |
| `later` | 5 min | – |
| `nudgeTimeout` | 2 min | – |
| `warning`, `snooze`, `snoozeWindow`, `giveUp` | 10 s, 2 min, 1 h, 2 min | – |
| `logURL` | `~/Library/Logs/eye-break.log` | `EYE_BREAK_LOG` |

The overrides exist for testing with short timings; see "Testing with short timings" in the README.

## 10. Development

Build without installing:

```sh
swiftc -O src/*.swift -o eye-break
./eye-break            # runs the app (quits immediately if an installed copy is running)
./eye-break stats
```

There's no automated test suite in the repo yet. The Scheduler is built to be tested with fakes (see [§5](#5-architecture)). A test can compile `Settings.swift`, `Checks.swift`, `Log.swift` and `Scheduler.swift` together with its own `main.swift`, then drive `tick()`, `willSleep()`, `didWake()` and `screenLocked()` with a fake clock and fake probes.

Before a release, check by hand:

- [ ] The menu bar icon and menu appear and update.
- [ ] The reminder panel shows, counts down hands-off, and chimes.
- [ ] Later, Skip, and an ignored reminder behave as in §6.2.
- [ ] Locking the screen and closing the lid during a reminder log `natural` and dismiss it.
- [ ] A due break waits while the camera is on.
- [ ] It starts at login, and Quit keeps it off until the next login.
- [ ] Strict mode: warning, overlay on every screen, escape hatch.
