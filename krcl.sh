#!/bin/bash

curl -s https://krcl.org/shows/ > krcl_shows.html

INPUT="krcl_shows.html"

# Extract unique show names
scrape_shows() {
    grep -oP 'href="/(shows|programs)?/?[^"/]+/' "$INPUT" \
        | sed -E 's/^href="\/(shows|programs)?\/?([^"/]+)\/.*$/\2/' \
        | sort -u \
        | grep -vE '^(about|events|shows|blog|community-affairs|community-stories|galleries|govote|music-features|short-stories|support-1|sundance|listeners-community-radio-of-utah-is-a-501c3-registered-non-profit-ein-87-0322222|krcl-mix|random-shuffle|rss|news|programs|genre|support|donate|contact|volunteer|feedback|search)$'
}


# Scrape show schedule into schedule.tsv with slug column
echo -e "Day\tShow\tStart\tSlug" > schedule.tsv
DAY=""
while IFS= read -r line; do
    if [[ $line =~ \<th\>([A-Za-z]+)\<\/th\> ]]; then
        DAY="${BASH_REMATCH[1]}"
    fi
    if [[ $line =~ \<h6\>(.+)\<\/h6\> ]]; then
        SHOW=$(echo "${BASH_REMATCH[1]}" | sed 's/&amp;/\&/g')
        SLUG=$(echo "$SHOW" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed 's/^-//;s/-$//')
    fi
    if [[ $line =~ \<p\>(.+)\<\/p\> ]]; then
        TIME="${BASH_REMATCH[1]}"
        START=$(echo "$TIME" | cut -d'-' -f1 | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
        LOW=$(echo "$START" | tr '[:upper:]' '[:lower:]')
        if echo "$START" | grep -iqE 'am|pm'; then
            START24=$(date -d "$START" +%H:%M:%S 2>/dev/null)
        elif [[ "$LOW" == "midnight" ]]; then
            START24="00:00:00"
        elif [[ "$LOW" == "noon" ]]; then
            START24="12:00:00"
        else
            START24="unknown"
        fi
        if [[ -n "$DAY" && -n "$SHOW" && -n "$START24" ]]; then
            echo -e "$DAY\t$SHOW\t$START24\t$SLUG" >> schedule.tsv
            SHOW=""
        fi
    fi
done < "$INPUT"

# Prompt user for show + months
shows=($(scrape_shows))

if [ ${#shows[@]} -eq 0 ]; then
    echo "Failed to fetch show list. Exiting."
    exit 1
fi

echo "Available shows:"
for i in "${!shows[@]}"; do
    printf "%3d) %s\n" $((i+1)) "${shows[$i]}"
done

read -p "Select a show number: " show_number
selected_show="${shows[$((show_number-1))]}"

read -p "How many months back? (3/6/9/12/24/64): " months

# Try to match schedule entry by slug
schedule_match=$(awk -F '\t' -v slug="$selected_show" 'tolower($4) == slug {print $0; exit}' schedule.tsv)

if [ -z "$schedule_match" ]; then
    # Use fallback title from anchor tags
    fallback_title="${SLUG_TO_TITLE[$selected_show]}"
    if [ -z "$fallback_title" ]; then
        echo "Could not find a title for slug: $selected_show"
        exit 1
    fi

    echo "No schedule entry for '$fallback_title' — using fallback: Sunday 00:00:00"
    day_name="Sunday"
    start_time="00:00:00"
    weekday_target=7
else
    day_name=$(echo "$schedule_match" | cut -f1)
    start_time=$(echo "$schedule_match" | cut -f3)
    weekday_target=$(date -d "$day_name" +%u)
    echo "Auto-detected: $day_name ($weekday_target), $start_time"
fi


# Begin downloading
base_url="https://krcl-media.s3.us-west-000.backblazeb2.com/audio/$selected_show"

mkdir -p "$selected_show"
cd "$selected_show" || exit 1

start_date=$(date +%Y-%m-%d)
end_date=$(date -d "$start_date -$months months" +%Y-%m-%d)
current_date="$start_date"

while [[ "$current_date" > "$end_date" ]]; do
    weekday=$(date -d "$current_date" +%u)
    if [[ "$weekday" -eq "$weekday_target" ]]; then
        filename="${selected_show}_${current_date}_${start_time//:/-}.mp3"
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
