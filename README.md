# ThinkPad keyboard backlight: ambient mode

Personal fork maintained by [jordanneenan](https://github.com/jordanneenan).
Based on [alexanderpuschkinberlin's widget](https://github.com/alexanderpuschkinberlin/omarchy-keyboard-backlight), under the original MIT license.

This fork adds optional webcam-based ambient lighting. It has been tested on a
ThinkPad X1 Carbon Gen 6 with the Chicony visible-light camera; it is not yet a
general camera-support implementation. Ambient mode is disabled by default.
[Upstream feature discussion](https://github.com/alexanderpuschkinberlin/omarchy-keyboard-backlight/issues/1).

## Installation and updates

For a fresh installation:

```sh
omarchy plugin add https://github.com/jordanneenan/omarchy-keyboard-backlight.git --enable
```

This fork keeps the upstream plugin ID to preserve settings and bar placement.
Do not install both versions side by side. To switch an existing installation,
first back up the plugin directory and shell.json, and commit or back up any local
changes. Then point its `origin` at this fork and update:

```sh
git -C ~/.config/omarchy/plugins/io.github.alexanderpuschkinberlin.keyboard-backlight remote set-url origin https://github.com/jordanneenan/omarchy-keyboard-backlight.git
omarchy plugin update io.github.alexanderpuschkinberlin.keyboard-backlight --yes
omarchy restart shell
```

Omarchy updates fetch `origin HEAD` and fast-forward the installed checkout. With
`origin` pointing here, they follow this fork's default branch. Upstream changes
do not arrive automatically; review and merge them into this fork when desired.
Local uncommitted or divergent changes may prevent an update. Keep development in
a separate checkout and push completed changes here before updating the plugin.
There is no automatic upstream-sync workflow in this fork.

## Everyday use

Click the keyboard-light bar icon to open the panel. Choose **Off**, **Medium**
(level 1), or **Bright** (level 2). Right-clicking the icon cycles these levels.
Either manual action pauses both automatic systems; **Resume automatic control**
resumes them. The pause survives shell reloads and login. The hardware Fn shortcut
is outside this widget: an automatic sample can overwrite an Fn-selected level.

**Ambient mode** uses the visible-light webcam every 2 minutes. A dark scene
selects Bright, an intermediate scene Medium, and a bright scene Off. The panel
shows the latest intensity and smoothed intensity. Camera activity lasts roughly
one second per successful sample, rather than keeping the camera open.

Priority is: manual pause → successful ambient sensing → enabled time schedule.
If sensing fails (including camera busy), the schedule applies immediately. If
the schedule is disabled, the last keyboard level remains. Sensing retries at
the next interval. Disabling ambient mode resumes the enabled schedule. Enabling
either automatic control clears the manual pause. Existing schedule hours are
preserved; the schedule sets Medium during its night period and Off during day.

## Calibration

Readings are a **relative 0–255 grayscale intensity**, not lux. Initial boundaries
are 35 (dark) and 105 (bright). These are starting values, not a measurement of
your room. Fixed exposure makes comparison more useful than automatic exposure,
but camera processing, screen glow, face position, windows and viewing direction
still influence readings. A covered lens looks dark and may select Bright.

1. Open the physical camera shutter and position the screen as you normally use it.
2. Enable Ambient mode. In a room where you want Bright, note the displayed Light
   value after a sample. Repeat for a room where Medium is appropriate, and then
   for a bright room where you want Off. Do not cover the camera to simulate darkness.
3. With the panel's −/+ buttons, place **Dark boundary** between the Bright-room
   and Medium-room readings. Place **Bright boundary** between the Medium-room
   and Off-room readings. For example, readings 15, 65, 150 suggest boundaries
   around 40 and 105. Each click adjusts five units and starts a new measurement
   when the current one is finished; otherwise wait for the next interval.
4. Observe natural lighting transitions and refine. Boundaries must be at least
   20 units apart. If your three readings overlap, camera sensing cannot reliably
   separate those situations; use the schedule/manual controls.

The smoothed value is 65% previous + 35% current. Switching uses an eight-unit
hysteresis margin: Bright remains until dark+8, Off remains until bright−8;
Medium leaves below dark−8 or above bright+8. The first sample uses the boundaries
without that margin. Large lighting changes may take several 2-minute samples.

## Camera, privacy and dependencies

The helper uses this stable visible-camera path (not the infrared camera):
`/dev/v4l/by-id/usb-Chicony_Electronics_Co._Ltd._Integrated_Camera-video-index0`.
It needs Python 3, FFmpeg, v4l2-ctl (v4l-utils), fuser (psmisc), brightnessctl,
and the existing Omarchy/Quickshell environment. Install these dependencies before using ambient mode.

A sample checks whether the camera is in use, saves its exposure controls, sets
manual exposure to 156 × 100 microseconds (15.6 ms), disables dynamic frame rate,
and captures twelve 320×240 frames. FFmpeg reduces them to 32×24 grayscale; only
the last three contribute to the mean. Frames live in process memory, are never
written to disk, and are never uploaded. No AI model or network service runs in
this feature. Gemini/Codex are development tools only.

The helper restores exposure time, dynamic frame rate and automatic-exposure mode
in a finally block, including on ordinary failures, timeout and SIGTERM. Each
command has a timeout (capture: eight seconds; control commands: three seconds).
An advisory lock prevents concurrent helper samples. A process killed with
SIGKILL or a power loss cannot run cleanup. No software check can eliminate the
small race if a video-call app opens the camera between the busy check and capture.
The camera activity LED may blink every 2 minutes. Sampling consumes some power.
This camera exposes no separate gain control; internal processing may still vary.

## Troubleshooting and diagnostics

- **Camera busy:** close the video application, or leave it open and let schedule
  fallback work. No camera controls are changed when the busy check detects use.
- **Always Bright:** check the shutter, lighting and thresholds. A dark/covered
  camera cannot distinguish a dark room from an obstructed lens.
- **Slow changes:** smoothing and hysteresis intentionally suppress flicker.
- **Camera unavailable / permission denied:** verify the stable device path and
  normal logged-in device access. Do not change global device permissions.
- **Camera restoration failed:** the panel reports it. Turn Ambient mode off;
  inspect controls with the command below before starting a call.
- **Manual selection sticks:** click Resume automatic control.

One diagnostic measurement (briefly activates camera, does not change keyboard):

```sh
~/.config/omarchy/plugins/io.github.alexanderpuschkinberlin.keyboard-backlight/bin/ambient-light
v4l2-ctl -d /dev/video2 --get-ctrl=auto_exposure,exposure_time_absolute,exposure_dynamic_framerate
```

A successful JSON result includes `reading`, `average`, and `mode` (`high`, `low`,
`off`). Failure returns `ok: false`, a readable error, and exit status 1. Advanced
helper options are listed with `--help`; `--camera` changes only a standalone
measurement. The widget uses the default stable path defined at the top of the
helper. This implementation is tailored to this camera's controls and formats.

## Files and settings

- `BarWidget.qml`: timer, classification result handling, automation precedence,
  manual pause, setting persistence and keyboard actions.
- `Panel.qml`: brightness, ambient status, boundaries and schedule controls.
- `bin/ambient-light`: bounded capture, restoration, smoothing and classification.
- `bin/keyboard-backlight`: existing brightnessctl helper, unchanged.
- `manifest.json`: defaults and schema for the local plugin.
- `~/.config/omarchy/shell.json`: this plugin's persisted settings:
  `ambientEnabled`, `manualOverride`, `ambientDarkThreshold`,
  `ambientBrightThreshold`, and the original schedule settings.

No user service or background daemon was installed. The widget owns the timer.
Updates from this fork preserve the fork feature set. Replacing the installation
with upstream code removes these additions; keep a backup before switching.

## Validation and rollback

Run the portable unit tests from the repository root:

```sh
python -m unittest discover -s tests -v
omarchy plugin validate .
```

Tests cover the three modes, hysteresis, smoothing, invalid thresholds, busy-camera
protection, and restoration after a simulated capture failure. Live development
checks verified camera capture and restoration, all keyboard levels, the rendered
panel, persistent manual pause, busy-camera schedule fallback, and recovery.
Cross-room accuracy and other webcam models have not been tested.

For immediate disablement, switch Ambient mode off in the panel. To restore an
older version, restore your backed-up plugin directory and its settings entry,
then run `omarchy restart shell`. Preserve unrelated settings when restoring
shell.json. To return to upstream, use your original upstream backup or a clean
upstream checkout: changing origin alone cannot fast-forward a diverged fork back
to upstream. Keep a backup of the fork before switching.

## Local diagnostic IPC

The drawer hosts the widget, so the normal top-level plugin toggle does not open
it. These commands work with its dedicated local diagnostic target:

```sh
omarchy-shell io.github.alexanderpuschkinberlin.keyboard-backlight.ambient status
omarchy-shell io.github.alexanderpuschkinberlin.keyboard-backlight.ambient open
omarchy-shell io.github.alexanderpuschkinberlin.keyboard-backlight.ambient sample
omarchy-shell io.github.alexanderpuschkinberlin.keyboard-backlight.ambient manual off
omarchy-shell io.github.alexanderpuschkinberlin.keyboard-backlight.ambient resume
```

`status` is read-only; `open` shows the panel; `sample` respects manual pause;
`manual off` pauses automation and sets Off; `resume` clears pause and samples.
After editing widget code, use `omarchy restart shell` if the drawer still uses
its cached version. No restart is needed for ordinary panel settings changes.
