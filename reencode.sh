#!/bin/bash

SAVEIFS=$IFS
IFS=$(echo -en "\n\b")

# Set Epoch time for temp files
EPOCH=$(date +%s)

# Directory to search
SEARCH_DIR=$1

# Manifest file to save filenames
MANIFEST_FILE="/tmp/reencode-manifest.out.$EPOCH"

# Cleanup files left over from download clients
echo
echo "Search directory set to $SEARCH_DIR"
echo
echo "Cleaning up from newsgroup downloads..."
echo
echo "Removing NFOs..."
find $SEARCH_DIR -type f -iname '*.nfo*' -exec rm {} +
rm -rf $SEARCH_DIR/*.nfo
echo "Removing SFVs/SRRs..."
find $SEARCH_DIR -type f -iname '*.sfv*' -exec rm {} +
find $SEARCH_DIR -type f -iname '*.srr*' -exec rm {} +
echo "Removing samples..."
rm -rf $SEARCH_DIR/*sample*
rm -rf $SEARCH_DIR/*Sample*
echo "Removing VTXs..."
find $SEARCH_DIR -type f -name '*.vtx*' -exec rm {} +
echo "Removing web content..."
find $SEARCH_DIR -type f -iname '*jpg*' -exec rm {} +
find $SEARCH_DIR -type f -iname '*url*' -exec rm {} +
find $SEARCH_DIR -type f -iname '*htm*' -exec rm {} +
find $SEARCH_DIR -type f -iname '*thumb*' -exec rm {} +
echo "Removing RARs/PARs..."
find $SEARCH_DIR -type f -iname '*par*' -exec rm {} +
find $SEARCH_DIR -type f -iname '*rar*' -exec rm {} +
echo "Removing empty files and directories..."
find $SEARCH_DIR -type d -empty -delete
find $SEARCH_DIR -type f -empty -delete
echo "Removing files without extensions..."
find $SEARCH_DIR -type f  ! -name "*.*"  -delete
echo
echo "Checking codecs for files..."

# Function to check codec
check_codec() {
    local file="$1"
    codec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null)
    if [ "$codec" != "hevc" ]; then
        echo "$file" >> "$MANIFEST_FILE"
    fi
}

# Main loop to check each file
find "$SEARCH_DIR" -type f -print0 | while IFS= read -r -d '' file; do
    check_codec "$file"
done

# Count number of files to encode in the manifest, then loop those through ffmpeg
FILES_TO_ENCODE=$(cat $MANIFEST_FILE | egrep -iv 'x265|265|hevc' | egrep -i 'mp4|mpg|mkv|avi|wmv|mov|flv' | wc -l)
echo
echo "Number of files to encode: $FILES_TO_ENCODE"
echo
echo "Encoding files to x265 (HEVC)..."
echo
for BASEFILE in `cat $MANIFEST_FILE | egrep -iv 'x265|265|hevc' | egrep -i 'mp4|mpg|mkv|avi|wmv|mov|flv'`; do echo "$BASEFILE" && yes | ffmpeg -loglevel quiet -stats -i "$BASEFILE" -c:v libx265 "${BASEFILE%.*}-x265.mp4" && rm -rf "$BASEFILE"; done
echo
echo "Done."
echo

# Remove existing manifest file
rm -f "$MANIFEST_FILE"
