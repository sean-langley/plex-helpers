#!/bin/bash

RAW_DIR="$HOME/Rips/raw"
ENCODED_DIR="$HOME/Rips/encoded"

mkdir -p "$RAW_DIR" "$ENCODED_DIR"

echo
echo "Scanning for disc..."

if ! makemkvcon -r info disc:0 >/dev/null 2>&1; then
    echo "No disc detected."
    exit 1
fi

echo "Disc detected."

echo
read -p "Select media type for disc:

1. TV
2. Movie
: " TYPE

echo
read -p "Enter title: " TITLE

if [[ "$TYPE" == "1" ]]; then
    read -p "Season number: " SEASON
fi

echo
echo "Scanning titles..."

# List all titles with duration
TITLES=$(makemkvcon -r info disc:0 | grep MSG:3028 | sed -E 's/.*,"([0-9]+)","[0-9]+","([0-9:]+)".*/\1 \2/')

if [[ -z "$TITLES" ]]; then
    echo "No titles detected."
    exit 1
fi

echo
if [[ "$TYPE" == "1" ]]; then
    echo "Titles found:"
    echo "$TITLES" | nl
    echo
    read -p "Starting episode number: " START_EP
    EP=$START_EP

    echo
    echo "Ripping TV episodes (min 900s)..."
    echo
    makemkvcon mkv --minlength=900 disc:0 all "$RAW_DIR"

    # Rename sequentially
    for FILE in "$RAW_DIR"/*.mkv; do
        NEWNAME="$RAW_DIR/${TITLE}.S$(printf "%02d" $SEASON)E$(printf "%02d" $EP).mkv"
        mv "$FILE" "$NEWNAME"
        EP=$((EP+1))
    done

else
    # Movie: pick only titles longer than 3000s (~50min)
    echo "Ripping main movie (min 3000s)..."
    echo
    makemkvcon mkv --minlength=3000 disc:0 all "$RAW_DIR"

    # Rename the longest file
    MOVIE_FILE=$(ls -t "$RAW_DIR"/*.mkv | head -n 1)
    NEWNAME="$RAW_DIR/${TITLE}.mkv"
    mv "$MOVIE_FILE" "$NEWNAME"
fi

echo
echo "Encoding..."
for FILE in "$RAW_DIR"/*.mkv; do
    BASENAME=$(basename "$FILE")
    OUTFILE="$ENCODED_DIR/$BASENAME"

    echo "Encoding $BASENAME"
    ffmpeg -y -i "$FILE" \
        -c:v hevc_videotoolbox \
        -q:v 65 \
        -c:a copy \
        "$OUTFILE"
done

echo
echo "Cleaning raw files..."
rm "$RAW_DIR"/*.mkv

echo
echo "Ejecting disc..."
drutil eject

echo
echo "Done."
echo
