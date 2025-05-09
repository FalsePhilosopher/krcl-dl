#!/bin/bash

dir="$(pwd)"
input="$dir/krcl_shows.html"
schedule_file="$dir/schedule.tsv"

trap 'cleanup' SIGINT

cleanup() {
    echo -e "\nInterrupted or exiting, cleaning up now."
    rm "$input"
    rm "$schedule_file"
    kill 0
    exit 1
}

curl -s https://krcl.org/shows/ > krcl_shows.html

scrape_shows() {
    grep -oP 'href="/(shows|programs)?/?[^"/]+/' "$input" \
        | sed -E 's/^href="\/(shows|programs)?\/?([^"/]+)\/.*$/\2/' \
        | sort -u \
        | grep -vE '^(about|events|shows|blog|community-affairs|community-stories|galleries|govote|music-features|short-stories|support-1|sundance|listeners-community-radio-of-utah-is-a-501c3-registered-non-profit-ein-87-0322222|krcl-mix|cdn-images.mailchimp.com|cdn.jsdelivr.net|random-shuffle|rss|news|programs|genre|support|donate|contact|volunteer|feedback|search)$'
}

echo -e "Day\tShow\tStart\tSlug" > schedule.tsv
DAY=""
while IFS= read -r line; do
    if [[ $line =~ \<th\>([A-Za-z]+)\<\/th\> ]]; then
        DAY="${BASH_REMATCH[1]}"
    fi
    if [[ $line =~ \<h6\>(.+)\<\/h6\> ]]; then
        SHOW="${BASH_REMATCH[1]//&amp;/&}"
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
done < "$input"

mapfile -t shows < <(scrape_shows)
if [ ${#shows[@]} -eq 0 ]; then
    echo "Failed to fetch show list. Exiting."
    exit 1
fi
echo "Available shows:"
for i in "${!shows[@]}"; do
    printf "%3d) %s\n" $((i+1)) "${shows[$i]}"
done
read -rp "Select a show number: " show_number
selected_show="${shows[$((show_number-1))]}"
read -rp "How many months back? (3/6/9/12/24/64): " months

# Try to match schedule entry by slug
schedule_match=$(awk -F '\t' -v slug="$selected_show" 'tolower($4) == slug {print $0; exit}' schedule.tsv)
if [ -z "$schedule_match" ]; then
    # If no match found, use the selected_show name
    echo "Could not find a schedule entry for '$selected_show'."
    read -rp "What time does '$selected_show' start? (HH:MM format, 24-hour clock): " user_time
    # Validate user input
    while [[ ! "$user_time" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; do
        echo "Invalid time format. Please enter the time in HH:MM format (24-hour clock)."
        read -rp "Enter the start time for '$selected_show' (HH:MM format, 24-hour clock): " user_time
    done
    start_time="${user_time//:/-}-00"
    day_name="Sunday"  # Defaulting to Sunday, adjust as needed
    weekday_target=7   # Sunday = 7
else
    day_name=$(echo "$schedule_match" | cut -f1)
    start_time=$(echo "$schedule_match" | cut -f3 | sed 's/:/-/g')
    weekday_target=$(date -d "$day_name" +%u)
    echo "Auto-detected: $day_name ($weekday_target), $start_time"
fi

base_url="https://krcl-media.s3.us-west-000.backblazeb2.com/audio/$selected_show"
mkdir -p "$selected_show"
cd "$selected_show" || exit 1
start_date=$(date +%Y-%m-%d)
end_date=$(date -d "$start_date -$months months" +%Y-%m-%d)
current_date="$start_date"

if [[ "$start_time" == "unknown" ]]; then
    echo "The start time for the show '$selected_show' is unknown."
    read -rp "Please enter the start time for this show (HH:MM format, 24-hour clock ie 19:00 for 7 p.m): " user_time
    # Validate user input
    while [[ ! "$user_time" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; do
        echo "Invalid time format. Please enter the time in HH:MM format (24-hour clock)."
        read -rp "Enter the start time for this show (HH:MM format, 24-hour clock): " user_time
    done
    # Format the time into 22-00-00 format
    start_time="${user_time//:/-}-00"
fi

while [[ "$current_date" > "$end_date" ]]; do
    weekday=$(date -d "$current_date" +%u)
    if [[ "$weekday" -eq "$weekday_target" ]]; then
        formatted_start_time="${start_time//:/-}"
        filename="${selected_show}_${current_date}_${formatted_start_time}.mp3"
        file_url="$base_url/$filename"
        if [[ -f "$filename" ]]; then
            echo "Already downloaded: $filename, skipping."
        else
            if wget -q --show-progress --no-use-server-timestamps "$file_url"; then
                echo "All done"
            else
                echo "not found, skipping."
            fi
        fi
    fi
    current_date=$(date -d "$current_date -1 day" +%Y-%m-%d)
done

read -rp "Download more shows? [y/N]: " answer
case "$answer" in
    [Yy]*) exec "$0";;
    *) cleanup;;
esac
