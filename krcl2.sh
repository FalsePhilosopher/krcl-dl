#!/bin/bash

# Fetch the list of shows
SHOWS_JSON=$(curl -s "https://krcl.studio.creek.org/api/archives/shows-list")

# Display the list of shows with sequential numbering
echo "Available Shows:"
SHOWS=$(echo "$SHOWS_JSON" | jq -r '.data[] | "\(.id) \(.title)"')
declare -a SHOW_IDS
INDEX=1
while IFS= read -r SHOW; do
  SHOW_ID=$(echo "$SHOW" | awk '{print $1}')
  SHOW_TITLE=$(echo "$SHOW" | cut -d' ' -f2-)
  SHOW_IDS+=("$SHOW_ID")
  echo "$INDEX: $SHOW_TITLE"
  INDEX=$((INDEX + 1))
done <<< "$SHOWS"

# Prompt user for selection
read -p "Enter the number of the show you want to download: " SHOW_INDEX
if [[ -n "${SHOW_IDS[$((SHOW_INDEX - 1))]}" ]]; then
  SHOW_ID="${SHOW_IDS[$((SHOW_INDEX - 1))]}"
else
  echo "Invalid selection."
  exit 1
fi

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
