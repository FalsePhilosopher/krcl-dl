#!/bin/bash

# REQUIREMENTS: wget, grep, sed, awk, date, basename

set -e

# Function to scrape live show list (NO echo here)
scrape_shows() {
    curl -s https://krcl.org/shows/ | grep -oP '(?<=href="/shows/)[^"/]+' | sort -u | grep -vE '^(about|events|shows|rss|news|programs|genre|support)'
    curl -s https://krcl.org/shows/ | grep -oP '(?<=href="/)[^"/]+' | sort -u | grep -vE '^(about|events|shows|rss|news|programs|genre|support)'
}

# Now safe to echo separately
echo "Scraping live show list from KRCL..."
shows=($(scrape_shows))

if [ ${#shows[@]} -eq 0 ]; then
    echo "Failed to fetch show list. Exiting."
    exit 1
fi

echo "Available shows:"
for i in "${!shows[@]}"; do
    printf "%3d) %s\n" $((i+1)) "${shows[$i]}"
done

# User selects show
read -p "Select a show number: " show_number
selected_show="${shows[$((show_number-1))]}"

# Get user preferences
read -p "How many months back? (3/6/9/12/24/64): " months
# Confirm
echo "Downloading $selected_show for the last $months months, every $weekday_target at $start_time..."

base_url="https://krcl-media.s3.us-west-000.backblazeb2.com/audio/$selected_show"

mkdir -p "$selected_show"
cd "$selected_show" || exit 1

start_date=$(date +%Y-%m-%d)
end_date=$(date -d "$start_date -$months months" +%Y-%m-%d)

current_date="$start_date"

while [[ "$current_date" > "$end_date" ]]; do
    weekday=$(date -d "$current_date" +%u)
    if [[ "$weekday" -eq "$weekday_target" ]]; then
        filename="${selected_show}_${current_date}_${start_time}.mp3"
        file_url="$base_url/$filename"

        if [[ -f "$filename" ]]; then
            echo "Already downloaded: $filename, skipping."
        else
            echo -n "Checking $filename... "
            if wget --spider -q "$file_url"; then
                echo "found! Downloading..."
                wget -q --show-progress "$file_url"
            else
                echo "not found, skipping."
            fi
        fi
    fi
    current_date=$(date -d "$current_date -1 day" +%Y-%m-%d)
done

echo "Done!"
