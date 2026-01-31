#!/bin/bash
#
# NVIDIA Adaptive VOD Transcoder
# Monitors a directory for new MP4 files and transcodes them to multiple resolutions
# using NVIDIA hardware acceleration (NVENC/CUVID)
#

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# Directories and files (can be overridden via environment variables)
WATCH_DIR="${WATCH_DIR:-/home/lab/sportfiles}"
STATE_DIR="${STATE_DIR:-/home/lab}"
LOG_FILE="${LOG_FILE:-${SCRIPT_DIR}/transcoder.log}"

readonly OLD_LIST="${STATE_DIR}/old_pwd.lst"
readonly NEW_LIST="${STATE_DIR}/new_pwd.lst"

# Polling interval in seconds
readonly POLL_INTERVAL="${POLL_INTERVAL:-10}"

# FFmpeg thread configuration
readonly VIDEO_THREADS=2
readonly AUDIO_THREADS=8
readonly FILTER_THREADS=2
readonly THREAD_QUEUE_SIZE=512

# Audio settings
readonly AUDIO_SAMPLE_RATE=44100
readonly AUDIO_CHANNELS=2

# ============================================================================
# Logging functions
# ============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    local log_line="[${timestamp}] [${level}] ${message}"
    echo "${log_line}"
    echo "${log_line}" >> "${LOG_FILE}"
}

log_info()  { log "INFO"  "$@"; }
log_warn()  { log "WARN"  "$@"; }
log_error() { log "ERROR" "$@"; }

log_separator() {
    local sep="================================================================"
    echo "${sep}"
    echo "${sep}" >> "${LOG_FILE}"
}

# ============================================================================
# Utility functions
# ============================================================================

check_dependencies() {
    local deps=("ffmpeg" "ffprobe")
    local missing=()

    for dep in "${deps[@]}"; do
        if ! command -v "${dep}" &> /dev/null; then
            missing+=("${dep}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi

    # Check for NVIDIA GPU support
    if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "h264_nvenc"; then
        log_error "NVIDIA encoder (h264_nvenc) not available"
        exit 1
    fi

    log_info "All dependencies verified"
}

validate_directories() {
    if [[ ! -d "${WATCH_DIR}" ]]; then
        log_error "Watch directory does not exist: ${WATCH_DIR}"
        exit 1
    fi

    if [[ ! -d "${STATE_DIR}" ]]; then
        log_error "State directory does not exist: ${STATE_DIR}"
        exit 1
    fi

    # Ensure log file is writable
    touch "${LOG_FILE}" 2>/dev/null || {
        log_error "Cannot write to log file: ${LOG_FILE}"
        exit 1
    }
}

# ============================================================================
# Video analysis functions
# ============================================================================

get_video_resolution() {
    local file="$1"
    ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=width,height \
        -of csv=s=x:p=0 \
        "$file" 2>/dev/null
}

get_video_bitrate() {
    local file="$1"
    ffprobe -v error \
        -select_streams v:0 \
        -show_entries stream=bit_rate \
        -of default=noprint_wrappers=1:nokey=1 \
        "$file" 2>/dev/null
}

# ============================================================================
# Resolution and bitrate calculation
# ============================================================================

# Calculate adaptive resolutions based on source
# HD:  2/3 of original
# SD:  1/2 of original
calculate_resolutions() {
    local width="$1"
    local height="$2"

    # Ensure dimensions are even (required for video encoding)
    local hd_width=$(( (width * 2 / 3 + 1) / 2 * 2 ))
    local hd_height=$(( (height * 2 / 3 + 1) / 2 * 2 ))
    local sd_width=$(( (width / 2 + 1) / 2 * 2 ))
    local sd_height=$(( (height / 2 + 1) / 2 * 2 ))

    echo "${hd_width}x${hd_height} ${sd_width}x${sd_height}"
}

# Calculate adaptive bitrates
# HD:  1/2 of original
# SD:  1/3 of original
calculate_bitrates() {
    local bitrate_bps="$1"
    local original_kbps=$(( bitrate_bps / 1024 ))
    local hd_kbps=$(( original_kbps / 2 ))
    local sd_kbps=$(( original_kbps / 3 ))

    echo "${original_kbps} ${hd_kbps} ${sd_kbps}"
}

# ============================================================================
# Transcoding functions
# ============================================================================

transcode_video() {
    local input="$1"
    local output="$2"
    local resolution="$3"
    local bitrate="$4"
    local preset="$5"
    local profile="$6"

    log_info "Transcoding: ${input} -> ${output}"
    log_info "  Resolution: ${resolution}, Bitrate: ${bitrate}K, Preset: ${preset}, Profile: ${profile}"

    if ffmpeg -n \
        -threads:v "${VIDEO_THREADS}" \
        -threads:a "${AUDIO_THREADS}" \
        -filter_threads "${FILTER_THREADS}" \
        -thread_queue_size "${THREAD_QUEUE_SIZE}" \
        -vsync 1 \
        -hwaccel cuvid \
        -c:v h264_cuvid \
        -resize "${resolution}" \
        -i "$input" \
        -c:v h264_nvenc \
        -b:v "${bitrate}K" \
        -g 48 \
        -keyint_min 48 \
        -preset "${preset}" \
        -profile:v "${profile}" \
        -c:a aac \
        -ar "${AUDIO_SAMPLE_RATE}" \
        -ac "${AUDIO_CHANNELS}" \
        "$output" \
        -loglevel warning 2>&1; then
        log_info "Successfully transcoded: ${output}"
        return 0
    else
        log_error "Failed to transcode: ${input} -> ${output}"
        return 1
    fi
}

process_video() {
    local input="$1"
    local base_name="${input%.mp4}"

    log_separator
    log_info "Processing: ${input}"

    # Get source video properties
    local resolution
    resolution=$(get_video_resolution "$input")
    if [[ -z "$resolution" ]]; then
        log_error "Failed to detect resolution for: ${input}"
        return 1
    fi

    local bitrate
    bitrate=$(get_video_bitrate "$input")
    if [[ -z "$bitrate" || "$bitrate" == "N/A" ]]; then
        log_warn "Could not detect bitrate, using default 5000 Kbps"
        bitrate=5120000
    fi

    local width height
    width=$(echo "$resolution" | cut -d'x' -f1)
    height=$(echo "$resolution" | cut -d'x' -f2)

    # Calculate adaptive parameters
    local resolutions
    resolutions=$(calculate_resolutions "$width" "$height")
    local hd_resolution sd_resolution
    hd_resolution=$(echo "$resolutions" | cut -d' ' -f1)
    sd_resolution=$(echo "$resolutions" | cut -d' ' -f2)

    local bitrates
    bitrates=$(calculate_bitrates "$bitrate")
    local original_kbps hd_kbps sd_kbps
    original_kbps=$(echo "$bitrates" | cut -d' ' -f1)
    hd_kbps=$(echo "$bitrates" | cut -d' ' -f2)
    sd_kbps=$(echo "$bitrates" | cut -d' ' -f3)

    # Log source info
    log_info "Source Info:"
    log_info "  File: ${input}"
    log_info "  Resolution: ${resolution}"
    log_info "  Bitrate: ${original_kbps} Kbps"

    log_info "Transcoding Plan:"
    log_info "  Stream 1 (FHD): ${resolution}, ${original_kbps}K, high/slow"
    log_info "  Stream 2 (HD):  ${hd_resolution}, ${hd_kbps}K, main/medium"
    log_info "  Stream 3 (SD):  ${sd_resolution}, ${sd_kbps}K, baseline/fast"

    # Transcode to multiple resolutions
    local success=0

    # FHD - Original resolution with optimized encoding
    if transcode_video "$input" "${base_name}_1080.mp4" \
            "$resolution" "$original_kbps" "slow" "high"; then
        ((success++))
    fi

    # HD - 720p equivalent
    if transcode_video "$input" "${base_name}_720.mp4" \
            "$hd_resolution" "$hd_kbps" "medium" "main"; then
        ((success++))
    fi

    # SD - 480p equivalent
    if transcode_video "$input" "${base_name}_480.mp4" \
            "$sd_resolution" "$sd_kbps" "fast" "baseline"; then
        ((success++))
    fi

    log_info "Completed ${success}/3 transcodes for: ${input}"
    log_separator

    return 0
}

# ============================================================================
# File discovery
# ============================================================================

find_mp4_files() {
    local output_file="$1"
    : > "$output_file"

    find "${WATCH_DIR}" -type f -name "*.mp4" \
        ! -name "*_1080.mp4" \
        ! -name "*_720.mp4" \
        ! -name "*_480.mp4" \
        -print >> "$output_file" 2>/dev/null || true
}

get_new_files() {
    if [[ ! -f "${OLD_LIST}" || ! -f "${NEW_LIST}" ]]; then
        return
    fi

    # Find files that are in new but not in old
    comm -13 <(sort "${OLD_LIST}") <(sort "${NEW_LIST}") 2>/dev/null || true
}

count_transcoded_files() {
    local pattern="$1"
    find "${WATCH_DIR}" -type f -name "*${pattern}" 2>/dev/null | wc -l
}

print_stats() {
    local total_files
    total_files=$(wc -l < "${NEW_LIST}" 2>/dev/null || echo 0)

    local fhd_count hd_count sd_count
    fhd_count=$(count_transcoded_files "_1080.mp4")
    hd_count=$(count_transcoded_files "_720.mp4")
    sd_count=$(count_transcoded_files "_480.mp4")

    log_separator
    log_info "Statistics:"
    log_info "  Total source files: ${total_files}"
    log_info "  Transcoded - FHD: ${fhd_count}, HD: ${hd_count}, SD: ${sd_count}"
    log_separator
}

# ============================================================================
# Signal handling
# ============================================================================

cleanup() {
    log_info "Received shutdown signal, cleaning up..."
    rm -f "${OLD_LIST}" "${NEW_LIST}" 2>/dev/null || true
    log_info "Transcoder stopped"
    exit 0
}

trap cleanup SIGINT SIGTERM SIGHUP

# ============================================================================
# Main loop
# ============================================================================

main() {
    log_info "Starting NVIDIA Adaptive VOD Transcoder"
    log_info "Watch directory: ${WATCH_DIR}"
    log_info "Log file: ${LOG_FILE}"
    log_info "Poll interval: ${POLL_INTERVAL}s"

    check_dependencies
    validate_directories

    while true; do
        # Build initial file list
        find_mp4_files "${OLD_LIST}"

        sleep "${POLL_INTERVAL}"

        # Build new file list
        find_mp4_files "${NEW_LIST}"

        # Get list of new files
        local new_files
        new_files=$(get_new_files)

        if [[ -n "$new_files" ]]; then
            print_stats

            while IFS= read -r file; do
                if [[ -f "$file" ]]; then
                    process_video "$file" || {
                        log_error "Failed to process: ${file}"
                    }
                fi
            done <<< "$new_files"
        fi
    done
}

# Run main function
main "$@"
