#!/bin/bash

SAVEIFS=$IFS
IFS=$(echo -en "\n\b")
THREADS=5
EPOCH=$(date +%s)
MANIFEST_FILE="/tmp/reencode-manifest.out.$EPOCH"

# Flags
CLEANUP_ONLY=false
DRY_RUN=false
DETAIL=false
POSITIONAL_ARGS=()

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS] <search_directory>"
    echo
    echo "Options:"
    echo "  --cleanup      Only clean up unnecessary files, skip encoding."
    echo "  --dry-run      Show what would be done, including space estimates, without making changes."
    echo "  --detail       Show detailed output (filenames of files being cleaned/encoded)."
    echo "  --threads N    Set number of threads (CPU cores) to use. Note: has no effect with VideoToolbox."
    echo "  -h, --help     Show this help message and exit."
    echo
    echo "Example:"
    echo "  $0 /videos                   # Cleanup + encode"
    echo "  $0 --cleanup /videos        # Only cleanup"
    echo "  $0 --dry-run /videos        # Simulate cleanup + encoding"
    echo "  $0 --detail --dry-run /videos   # Simulate with detailed output"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cleanup)
            CLEANUP_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --detail)
            DETAIL=true
            shift
            ;;
        --threads)
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                THREADS="$2"
                shift 2
            else
                echo "Error: --threads requires a numeric argument."
                exit 1
            fi
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done

# Restore positional arguments
set -- "${POSITIONAL_ARGS[@]}"

# Check for search directory
if [ -z "$1" ]; then
    echo "Error: No search directory provided."
    show_help
    exit 1
fi

SEARCH_DIR="$1"

echo
echo "Search directory set to $SEARCH_DIR"
echo
echo "Starting cleanup..."

TOTAL_CLEANUP_SIZE=0

# Get file size (GNU and BSD/macOS compatible)
get_file_size() {
    if stat --version >/dev/null 2>&1; then
        stat -c %s "$1"
    else
        stat -f %z "$1"
    fi
}

# Format file size
if command -v numfmt >/dev/null 2>&1; then
    format_size() {
        numfmt --to=iec "$1"
    }
else
    format_size() {
        echo "$1 bytes"
    }
fi

# Delete/simulate files
delete_files_by_pattern() {
    local pattern="$1"
    if [ "$DETAIL" = true ]; then
        echo "Removing: $pattern"
    fi
    if [ "$DRY_RUN" = true ]; then
        TEMP_FILE="/tmp/cleanup_size.$EPOCH.$RANDOM"
        : > "$TEMP_FILE"
        find "$SEARCH_DIR" -type f -iname "$pattern" -print0 | while IFS= read -r -d '' file; do
            size=$(get_file_size "$file" 2>/dev/null || echo 0)
            echo "$size" >> "$TEMP_FILE"
            if [ "$DETAIL" = true ]; then
                echo "[Dry Run] Would delete: $file ($(format_size $size))"
            fi
        done
        while read -r line; do
            TOTAL_CLEANUP_SIZE=$((TOTAL_CLEANUP_SIZE + line))
        done < "$TEMP_FILE"
        rm -f "$TEMP_FILE"
    else
        find "$SEARCH_DIR" -type f -iname "$pattern" -exec rm -f {} +
        if [ "$DETAIL" = true ]; then
            find "$SEARCH_DIR" -type f -iname "$pattern" -print
        fi
    fi
}

# Cleanup patterns
cleanup_patterns=(
    "*.nfo*" "*.sfv*" "*.srr*" "*sample*" "*.vtx*"
    "*jpg*" "*url*" "*htm*" "*thumb*" "*par*" "*rar*"
)

# Run cleanup
echo "Removing superfluous files..."
for pattern in "${cleanup_patterns[@]}"; do
    delete_files_by_pattern "$pattern"
done

# Remove empty dirs
echo "Removing empty directories..."
if [ "$DRY_RUN" = true ]; then
    find "$SEARCH_DIR" -type d -empty -print | while read -r dir; do
        if [ "$DETAIL" = true ]; then
            echo "[Dry Run] Would delete empty dir: $dir"
        fi
    done
else
    find "$SEARCH_DIR" -type d -empty -delete
    if [ "$DETAIL" = true ]; then
        find "$SEARCH_DIR" -type d -empty -print
    fi
fi

# Remove empty files
echo "Removing empty files..."
if [ "$DRY_RUN" = true ]; then
    find "$SEARCH_DIR" -type f -empty -print | while read -r file; do
        if [ "$DETAIL" = true ]; then
            echo "[Dry Run] Would delete empty file: $file"
        fi
    done
else
    find "$SEARCH_DIR" -type f -empty -delete
    if [ "$DETAIL" = true ]; then
        find "$SEARCH_DIR" -type f -empty -print
    fi
fi

# Remove files without extensions
echo "Removing files without extensions..."
if [ "$DRY_RUN" = true ]; then
    find "$SEARCH_DIR" -type f ! -name '*.*' -print | while read -r file; do
        if [ "$DETAIL" = true ]; then
            echo "[Dry Run] Would delete file without extension: $file"
        fi
    done
else
    find "$SEARCH_DIR" -type f ! -name '*.*' -delete
    if [ "$DETAIL" = true ]; then
        find "$SEARCH_DIR" -type f ! -name '*.*' -print
    fi
fi

# Summary of cleanup
if [ "$DRY_RUN" = true ]; then
    echo
    echo "[Dry Run] Estimated space to be freed from cleanup: $(format_size $TOTAL_CLEANUP_SIZE)"
fi

# Exit early if cleanup-only
if [ "$CLEANUP_ONLY" = true ]; then
    echo
    echo "Cleanup complete. Skipping encoding due to --cleanup flag."
    exit 0
fi

echo
echo "Checking codecs for files..."

# Codec check
check_codec() {
    local file="$1"
    codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name \
        -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    if [ "$codec" != "hevc" ]; then
        echo "$file" >> "$MANIFEST_FILE"
    fi
}

# Collect non-HEVC files
find "$SEARCH_DIR" -type f -print0 | while IFS= read -r -d '' file; do
    check_codec "$file"
done

# Count
FILES_TO_ENCODE=$(grep -iE '\.(mp4|mpg|mkv|avi|wmv|mov|flv)$' "$MANIFEST_FILE" | grep -ivE 'x265|265|hevc' | wc -l)
echo
echo "Number of files to encode: $FILES_TO_ENCODE"
echo

if [ "$FILES_TO_ENCODE" -eq 0 ]; then
    echo "No files need encoding."
    [ "$DRY_RUN" = false ] && rm -f "$MANIFEST_FILE"
    exit 0
fi

TOTAL_ENCODE_SIZE=0

# Encode files
if [ "$DRY_RUN" = true ]; then
    TEMP_ENCODE_FILE="/tmp/encode_size.$EPOCH.$RANDOM"
    : > "$TEMP_ENCODE_FILE"

    grep -iE '\.(mp4|mpg|mkv|avi|wmv|mov|flv)$' "$MANIFEST_FILE" | grep -ivE 'x265|265|hevc' | while read -r BASEFILE; do
        OUTPUT="${BASEFILE%.*}-x265.mp4"
        size=$(get_file_size "$BASEFILE" 2>/dev/null || echo 0)
        echo "$size" >> "$TEMP_ENCODE_FILE"
        if [ "$DETAIL" = true ]; then
            echo "[Dry Run] Would encode: $BASEFILE ($(format_size $size))"
            echo "[Dry Run] Would delete original: $BASEFILE"
        fi
    done

    while read -r line; do
        TOTAL_ENCODE_SIZE=$((TOTAL_ENCODE_SIZE + line))
    done < "$TEMP_ENCODE_FILE"
    rm -f "$TEMP_ENCODE_FILE"

    echo
    echo "[Dry Run] Estimated space being processed for encoding: $(format_size $TOTAL_ENCODE_SIZE)"
else
    grep -iE '\.(mp4|mpg|mkv|avi|wmv|mov|flv)$' "$MANIFEST_FILE" | grep -ivE 'x265|265|hevc' | while read -r BASEFILE; do
        OUTPUT="${BASEFILE%.*}-x265.mp4"
        echo "Encoding: $BASEFILE to $OUTPUT"

        HEIGHT=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
            -of default=noprint_wrappers=1:nokey=1 "$BASEFILE")

        if [ "$HEIGHT" -le 480 ]; then
            BV="700k"; MAXRATE="1200k"; BUFSIZE="2000k"
        elif [ "$HEIGHT" -le 720 ]; then
            BV="1500k"; MAXRATE="2500k"; BUFSIZE="6000k"
        elif [ "$HEIGHT" -le 1080 ]; then
            BV="2000k"; MAXRATE="4000k"; BUFSIZE="10000k"
        elif [ "$HEIGHT" -le 1440 ]; then
            BV="4000k"; MAXRATE="6000k"; BUFSIZE="16000k"
        else
            BV="8000k"; MAXRATE="10000k"; BUFSIZE="20000k"
        fi

        if [ "$DETAIL" = true ]; then
            echo "[DEBUG] Height: $HEIGHT ? Bitrate: $BV, Maxrate: $MAXRATE, Bufsize: $BUFSIZE"
        fi

        yes | ffmpeg -loglevel quiet -stats -i "$BASEFILE" \
            -c:v hevc_videotoolbox -b:v "$BV" -maxrate "$MAXRATE" -bufsize "$BUFSIZE" \
            -c:a copy "$OUTPUT"

        if [ $? -eq 0 ]; then
            echo "Encoded successfully: $OUTPUT"
            rm -f "$BASEFILE"
        else
            echo "Encoding failed for: $BASEFILE"
        fi
    done
    rm -f "$MANIFEST_FILE"
fi

# Restore IFS
IFS=$SAVEIFS

# End of script
