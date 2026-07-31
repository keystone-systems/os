---
title: Screen Recording
description: GPU-accelerated screen recording with optional audio capture
---

# Screen Recording

Keystone provides built-in screen recording capabilities using GPU-accelerated encoding. Record your screen with optional audio capture for documentation, tutorials, bug reports, and presentations.

## Quick Start

Record your screen in 30 seconds:

1. Press `Super+Escape` to open the Keystone menu
2. Navigate to "Capture" → "Screenrecord"
3. Recording starts immediately with a notification
4. Click the red recording indicator in Waybar to stop
5. Find your recording in `~/Videos/screenrecording-YYYY-MM-DD_HH-MM-SS.mp4`

**Tip:** The recording indicator appears in the center of your Waybar (status bar at the top). A single click stops recording.

## Recording Methods

### Method 1: Menu System (Easiest)

The most discoverable method for first-time users:

1. Press `Super+Escape` (or press the power button)
2. Select "Capture" from the main menu
3. Select "Screenrecord"
4. Recording starts immediately

### Method 2: Waybar Indicator

When recording is active, the Waybar shows a red indicator:

- **To stop recording:** Click the indicator once
- The indicator only appears when recording is active
- Location: Center section of Waybar, next to the clock

### Method 3: Command Line

For advanced users and scripting:

```bash
# Start basic recording (video only)
keystone-screenrecord

# Start recording with desktop audio
keystone-screenrecord --with-desktop-audio

# Start recording with microphone
keystone-screenrecord --with-microphone-audio

# Start recording with both audio sources
keystone-screenrecord --with-desktop-audio --with-microphone-audio

# Stop active recording
keystone-screenrecord --stop
```

**Toggle behavior:** Running `keystone-screenrecord` when a recording is already active will stop the current recording.

## Audio Configuration

Choose the right audio setup for your use case:

### Audio Decision Matrix

| Your Need         | Command                                                              | Best For                                                          |
| ----------------- | -------------------------------------------------------------------- | ----------------------------------------------------------------- |
| **Video only**    | `keystone-screenrecord`                                              | Bug reproduction, silent demos, screen captures without narration |
| **Desktop audio** | `keystone-screenrecord --with-desktop-audio`                         | App demos with sound effects, gameplay, browser tab audio         |
| **Microphone**    | `keystone-screenrecord --with-microphone-audio`                      | Tutorial voiceovers, presentations, explaining code               |
| **Both sources**  | `keystone-screenrecord --with-desktop-audio --with-microphone-audio` | Full presentations, live coding with explanations                 |

### Audio Source Details

**Desktop Audio** (`--with-desktop-audio`):

- Captures all system audio output (speakers)
- Includes: Browser tabs, music players, application sounds, notifications
- Uses PipeWire `default_output` device
- Excludes: Your microphone input

**Microphone Audio** (`--with-microphone-audio`):

- Captures input from your default microphone
- Uses PipeWire `default_input` device
- Clear for voiceovers and explanations

**Combined Audio**:

- Both audio sources are mixed into a single audio track
- Synchronized automatically
- Output format: AAC codec at 128 kbps

### Audio Tips

**No audio needed?** Just run `keystone-screenrecord` without flags. This keeps file sizes smaller and works perfectly for silent demonstrations.

**Testing audio before recording:** Use your system's audio settings to verify input/output devices are working. Run `pactl list sources` and `pactl list sinks` to see available devices.

**Muting specific applications:** Use PipeWire audio controls (like `pavucontrol` or `helvum`) to mute specific application audio while recording desktop audio.

## Output Management

### Default Location

Recordings are saved to:

1. **Custom directory** (if `KEYSTONE_SCREENRECORD_DIR` is set)
2. **XDG Videos directory** (typically `~/Videos`)
3. **Fallback** to `~/Videos` if neither is configured

### Filename Format

Files are automatically named with timestamps to prevent collisions:

```
screenrecording-YYYY-MM-DD_HH-MM-SS.mp4
```

**Example:**

```
~/Videos/screenrecording-2025-01-08_14-30-45.mp4
```

This format:

- Sorts chronologically in file browsers
- Avoids filename conflicts (unique per second)
- Makes it easy to find recent recordings

### Customizing Output Directory

Set a custom directory for recordings using an environment variable:

```bash
# Temporary (current terminal session)
export KEYSTONE_SCREENRECORD_DIR=~/Projects/my-project/recordings
keystone-screenrecord

# Permanent (add to ~/.zshrc or ~/.bashrc)
echo 'export KEYSTONE_SCREENRECORD_DIR=~/Projects/my-project/recordings' >> ~/.zshrc
```

**Important:** The directory must exist before recording starts. Create it with:

```bash
mkdir -p ~/Projects/my-project/recordings
```

### File Specifications

Recordings use these technical settings:

| Property        | Value                     | Notes                                             |
| --------------- | ------------------------- | ------------------------------------------------- |
| **Container**   | MP4                       | Compatible with all major platforms               |
| **Video Codec** | H.264 (AVC)               | Hardware-accelerated GPU encoding                 |
| **Frame Rate**  | 60 FPS                    | Smooth playback, captures fast motion             |
| **Resolution**  | Native monitor resolution | Matches your display (e.g., 1920x1080, 3840x2160) |
| **Audio Codec** | AAC                       | 128 kbps, standard quality                        |
| **Encoding**    | GPU-accelerated           | NVIDIA/Intel/AMD hardware encoder                 |

## Common Workflows

### Workflow 1: Recording a Coding Session

**Goal:** Capture your coding workflow for documentation or sharing with teammates.

**Setup:**

- Video only (no audio needed)
- Full screen recording
- Save to project directory

**Steps:**

```bash
export KEYSTONE_SCREENRECORD_DIR=~/Projects/my-project/docs/recordings
keystone-screenrecord
# Code and demonstrate
# Click Waybar indicator when done
```

**Why no audio?** Coding sessions often include background noise (Slack notifications, browser tabs) that can be distracting. Silent recordings keep the focus on the visual workflow.

### Workflow 2: Creating a Tutorial

**Goal:** Create an instructional video explaining how to use a feature or tool.

**Setup:**

- Microphone audio (your voice)
- Region or full screen recording
- Clear explanations

**Steps:**

1. Test your microphone first (speak and verify audio is working)
2. Start recording: `keystone-screenrecord --with-microphone-audio`
3. Speak clearly while demonstrating
4. Stop when done (click Waybar indicator)

**Tip:** Write a script or outline beforehand. This keeps explanations concise and reduces the need for editing.

### Workflow 3: App Demo with Sound

**Goal:** Demonstrate an application that produces audio (music player, game, browser app).

**Setup:**

- Desktop audio capture
- Full screen or window recording
- Capture app's native sounds

**Steps:**

```bash
keystone-screenrecord --with-desktop-audio
# Demonstrate the application
# Stop when done
```

**Use case:** Showing how a sound effect works, demonstrating audio playback, capturing game audio.

### Workflow 4: Full Presentation

**Goal:** Record a complete presentation with your voice and any demo audio.

**Setup:**

- Both desktop and microphone audio
- Full screen recording
- Professional capture

**Steps:**

```bash
keystone-screenrecord --with-desktop-audio --with-microphone-audio
# Present with slides and demos
# Your voice is captured along with any demo audio
# Stop when finished
```

**Best practices:**

- Close unnecessary applications (reduces background noise and distractions)
- Use a quality microphone for clearer voice capture
- Test audio levels beforehand (speak at normal volume)

## Troubleshooting

### "Screen recording directory does not exist"

**Problem:** Recording fails immediately with this notification.

**Solution:**

1. Check if your `KEYSTONE_SCREENRECORD_DIR` is set correctly:
   ```bash
   echo $KEYSTONE_SCREENRECORD_DIR
   ```
2. Create the directory:
   ```bash
   mkdir -p $KEYSTONE_SCREENRECORD_DIR
   ```
3. Or unset the variable to use default location:
   ```bash
   unset KEYSTONE_SCREENRECORD_DIR
   ```

**Prevention:** Always create custom directories before setting `KEYSTONE_SCREENRECORD_DIR`.

### No Audio in Recording

**Problem:** Video recorded successfully but no audio track exists.

**Solutions:**

**If you forgot audio flags:**

- Solution: Re-record with `--with-desktop-audio` or `--with-microphone-audio`
- Remember: Audio is opt-in, not automatic

**If you used audio flags but still no audio:**

1. Verify PipeWire is running:
   ```bash
   systemctl --user status pipewire
   ```
2. Check if audio devices are available:
   ```bash
   pactl list sources short  # Microphone inputs
   pactl list sinks short    # Desktop audio outputs
   ```
3. Test microphone:
   ```bash
   arecord -f cd -d 5 test.wav && aplay test.wav
   ```

**Common cause:** Audio device was muted or disconnected during recording.

### "Recording had to be force-killed. Video may be corrupted."

**Problem:** Recording process didn't shut down cleanly.

**What this means:**

- The video file exists but may be incomplete or corrupted
- Encoder didn't finalize the video properly

**Solutions:**

1. Try playing the video with VLC or mpv (they handle corrupted files better than default players)
2. If video won't play, re-record the content
3. If this happens frequently, check system resources (CPU, GPU, disk space)

**When it happens:**

- System suspended during recording
- Out of disk space mid-recording
- GPU encoder crashed

### Recording Won't Stop

**Problem:** Clicking Waybar indicator or running command doesn't stop recording.

**Solution:**

```bash
# Manually stop the recording process
keystone-screenrecord --stop

# If that fails, force-kill the process
pkill -9 gpu-screen-recorder
```

**Note:** Force-killing may result in corrupted video (see above).

### Files Are Very Large

**Problem:** Recording files are larger than expected.

**Why this happens:**

- 60 FPS recording captures 60 frames every second
- GPU encoding is high quality by default
- Higher resolutions (4K) create much larger files

**File size estimates:**

- **1080p (1920x1080):** ~50-100 MB per minute
- **1440p (2560x1440):** ~100-150 MB per minute
- **4K (3840x2160):** ~200-300 MB per minute

**Solutions:**

- Record shorter clips (stop and start between sections)
- Use video editing software to compress after recording
- Record at lower resolution (if your monitor supports multiple resolutions)

**Not a bug:** Keystone prioritizes quality over file size. Use external tools for compression if needed.

### Recording Doesn't Capture Specific Window

**Problem:** Want to record just one window, but Keystone records entire screen.

**Current limitation:** Keystone records via Wayland portal, which provides:

- Entire screen capture
- Region selection (rectangular area)
- No per-window selection

**Workarounds:**

1. Use region selection to capture just the window area
2. Fullscreen the application you want to record
3. Move the target window to its own workspace

**Future enhancement:** Window-specific capture may be added in future versions.

## Technical Details

For advanced users and contributors who need to understand the implementation:

### Recording Engine

**Tool:** `gpu-screen-recorder`

- GPU-accelerated encoding (NVIDIA/Intel/AMD)
- Low CPU overhead compared to CPU encoding
- Real-time encoding (no post-processing delay)

**Portal interface:** Uses Wayland portal protocol (`-w portal`)

- Secure screen capture method
- Works with Hyprland and other Wayland compositors
- No X11 dependencies

### Command Reference

The `keystone-screenrecord` script is a wrapper around gpu-screen-recorder with these flags:

```bash
gpu-screen-recorder \
  -w portal \                    # Wayland portal capture
  -f 60 \                        # 60 FPS
  -encoder gpu \                 # GPU hardware encoding
  -o "$filename" \               # Output file path
  -a default_output|default_input \  # Audio devices (optional)
  -ac aac                        # AAC audio codec
```

### Integration Points

**Waybar Status Indicator:**

- Signal-based updates using `RTMIN+8` (efficient, no polling)
- Icon appears only when `gpu-screen-recorder` process is active
- Click executes `keystone-screenrecord` (toggle behavior)

**Notification System:**

- Start: "Screen recording started" (2-second display)
- Stop: "Screen recording saved to $OUTPUT_DIR" (2-second display)
- Error: Critical notifications with 5-second display
- Uses `libnotify` for desktop notifications

**Process Management:**

- Clean shutdown: SIGINT signal with 5-second grace period
- Force shutdown: SIGKILL after timeout (may corrupt video)
- Single-instance enforcement (prevents concurrent recordings)

### Environment Variables

| Variable                    | Default                         | Description                            |
| --------------------------- | ------------------------------- | -------------------------------------- |
| `KEYSTONE_SCREENRECORD_DIR` | `$XDG_VIDEOS_DIR` or `~/Videos` | Custom output directory                |
| `XDG_VIDEOS_DIR`            | `~/Videos`                      | Standard XDG user directory for videos |

### File Format Details

**MP4 Container Structure:**

- Video track: H.264 (AVC1) with GPU encoding profile
- Audio track (optional): AAC-LC, 128 kbps, 44.1 kHz
- Metadata: Creation timestamp, duration, resolution

**Codec Profiles:**

- H.264 High Profile (for quality)
- Level 4.0 or higher (depends on resolution)
- YUV 4:2:0 color space

**Compatibility:**

- Plays on Windows (Windows Media Player, VLC)
- Plays on macOS (QuickTime, IINA)
- Plays on Linux (mpv, VLC, GNOME Videos)
- Uploads to YouTube, Vimeo, Discord, Slack

### Performance Characteristics

**CPU Usage:** <5% on average (GPU handles encoding)
**GPU Usage:** 10-20% (depends on resolution and encoder)
**RAM Usage:** ~50-100 MB for recording process
**Disk Write Speed:** 5-15 MB/s (depends on resolution)

**System Requirements:**

- GPU with hardware video encoding support (NVIDIA NVENC, Intel Quick Sync, AMD VCE)
- PipeWire audio server (for audio capture)
- Sufficient disk space (see file size estimates above)

## See Also

- [Desktop Specification](../specs/REQ-002-keystone-desktop.md) - Full requirements for screen recording (dt-record-001)
- [Screenshots Guide](../specs/REQ-002-keystone-desktop.md#screenshots-dt-shot-001) - Related capture functionality
- [Waybar Configuration](../modules/desktop/home/components/waybar.nix) - Status bar integration
- [gpu-screen-recorder GitHub](https://github.com/mateosss/gpu-screen-recorder) - Upstream project

## Contributing

Found an issue or have a feature request? See [CLAUDE.md](../CLAUDE.md) for contribution guidelines.

Common enhancement requests:

- Per-window capture (Wayland portal limitation)
- Variable frame rate (currently fixed 60 FPS)
- Custom video quality settings
- Pause/resume functionality
