#!/bin/bash

# Fetch the list of shows
SHOWS_JSON=$(curl -s "https://krcl.studio.creek.org/api/archives/shows-list")

# Display the list of shows
echo "Available Shows:"
echo "$SHOWS_JSON" | jq -r '.data[] | "\(.id): \(.title)"'

# Prompt user for selection
read -p "Enter the ID of the show you want to download: " SHOW_ID

# Fetch episodes for the selected show
EPISODES_JSON=$(curl -s "https://krcl.studio.creek.org/api/archives?showId=$SHOW_ID")

# Extract episode dates and audio URLs
echo "$EPISODES_JSON" | jq -r '.data[] | [.start[:10], .audio.url] | @tsv' |
while IFS=$'\t' read -r DATE URL; do
  if [[ -n "$URL" ]]; then
    FILENAME="${URL##*/}"
    echo "Downloading $DATE → $FILENAME"
    curl -L -o "$FILENAME" "$URL"
  else
    echo "Skipping $DATE — No audio URL available."
  fi
done
