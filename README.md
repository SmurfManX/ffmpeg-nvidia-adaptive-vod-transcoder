# NVIDIA Adaptive VOD Transcoder

Bash script that monitors a directory for new MP4 video files and automatically transcodes them to multiple adaptive bitrate streams using NVIDIA hardware acceleration (NVENC/CUVID).

## Features

- **Hardware Acceleration** - Uses NVIDIA CUVID for decoding and NVENC for encoding
- **Adaptive Bitrate** - Automatically creates 3 quality levels (1080p, 720p, 480p)
- **Smart Detection** - Monitors directory for new files, skips already transcoded
- **Configurable** - All settings via environment variables
- **Robust** - Error handling, dependency checks, graceful shutdown

## Requirements

- NVIDIA GPU with NVENC support (GTX 600+ / Quadro K series+)
- FFmpeg compiled with `--enable-nvenc --enable-cuvid`
- NVIDIA drivers installed
- Bash 4.0+

## Installation

```bash
git clone https://github.com/smurfmanx/ffmpeg-nvidia-adaptive-vod-transcoder.git
cd ffmpeg-nvidia-adaptive-vod-transcoder
chmod +x transcoder.sh
```

## Usage

### Basic

```bash
./transcoder.sh
```

### With Custom Configuration

```bash
# Set watch directory
WATCH_DIR=/data/videos ./transcoder.sh

# Full configuration
WATCH_DIR=/data/videos \
STATE_DIR=/var/lib/transcoder \
LOG_FILE=/var/log/transcoder.log \
POLL_INTERVAL=30 \
./transcoder.sh
```

### Run as Service (systemd)

Create `/etc/systemd/system/transcoder.service`:

```ini
[Unit]
Description=NVIDIA Adaptive VOD Transcoder
After=network.target

[Service]
Type=simple
User=your-user
Environment="WATCH_DIR=/data/videos"
Environment="LOG_FILE=/var/log/transcoder.log"
ExecStart=/path/to/transcoder.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable transcoder
sudo systemctl start transcoder
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `WATCH_DIR` | `/home/lab/sportfiles` | Directory to monitor for new videos |
| `STATE_DIR` | `/home/lab` | Directory for state files |
| `LOG_FILE` | `./transcoder.log` | Path to log file |
| `POLL_INTERVAL` | `10` | Seconds between directory scans |

## Output Streams

For each input file `video.mp4`, the transcoder creates:

| Stream | File | Resolution | Bitrate | Profile | Preset |
|--------|------|------------|---------|---------|--------|
| FHD | `video_1080.mp4` | Original | Original | high | slow |
| HD | `video_720.mp4` | 2/3 original | 1/2 original | main | medium |
| SD | `video_480.mp4` | 1/2 original | 1/3 original | baseline | fast |

## Log Output

```
[2024-01-26 12:30:45] [INFO] Starting NVIDIA Adaptive VOD Transcoder
[2024-01-26 12:30:45] [INFO] Watch directory: /data/videos
[2024-01-26 12:30:45] [INFO] All dependencies verified
================================================================
[2024-01-26 12:30:55] [INFO] Statistics:
[2024-01-26 12:30:55] [INFO]   Total source files: 150
[2024-01-26 12:30:55] [INFO]   Transcoded - FHD: 22, HD: 22, SD: 22
================================================================
[2024-01-26 12:30:55] [INFO] Processing: /data/videos/new_video.mp4
[2024-01-26 12:30:55] [INFO] Source Info:
[2024-01-26 12:30:55] [INFO]   File: /data/videos/new_video.mp4
[2024-01-26 12:30:55] [INFO]   Resolution: 1920x1080
[2024-01-26 12:30:55] [INFO]   Bitrate: 5888 Kbps
[2024-01-26 12:30:55] [INFO] Transcoding Plan:
[2024-01-26 12:30:55] [INFO]   Stream 1 (FHD): 1920x1080, 5888K, high/slow
[2024-01-26 12:30:55] [INFO]   Stream 2 (HD):  1280x720, 2944K, main/medium
[2024-01-26 12:30:55] [INFO]   Stream 3 (SD):  960x540, 1962K, baseline/fast
```

## Signals

- `SIGINT` (Ctrl+C) - Graceful shutdown
- `SIGTERM` - Graceful shutdown
- `SIGHUP` - Graceful shutdown

## License

MIT
