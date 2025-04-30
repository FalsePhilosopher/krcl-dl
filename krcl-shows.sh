#!/bin/bash

INPUT="krcl_shows.html"
DAY=""
echo -e "Day\tShow\tStart" > schedule.tsv

while IFS= read -r line; do
    # Detect day header
    if [[ $line =~ \<th\>([A-Za-z]+)\<\/th\> ]]; then
        DAY="${BASH_REMATCH[1]}"
    fi

    # Detect show title
    if [[ $line =~ \<h6\>(.+)\<\/h6\> ]]; then
        SHOW=$(echo "${BASH_REMATCH[1]}" | sed 's/&amp;/\&/g')
    fi

    # Detect show time
    if [[ $line =~ \<p\>(.+)\<\/p\> ]]; then
        TIME="${BASH_REMATCH[1]}"
        START=$(echo "$TIME" | cut -d'-' -f1 | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

        # Normalize lowercase for easier comparison
        LOW=$(echo "$START" | tr '[:upper:]' '[:lower:]')

        # Convert to 24-hour time
        if echo "$START" | grep -iqE 'am|pm'; then
            START24=$(date -d "$START" +%H:%M:%S 2>/dev/null)
        elif [[ "$LOW" == "midnight" ]]; then
            START24="00:00:00"
        elif [[ "$LOW" == "noon" ]]; then
            START24="12:00:00"
        else
            START24="unknown"
        fi

        # Save the entry
        if [[ -n "$DAY" && -n "$SHOW" && -n "$START24" ]]; then
            echo -e "$DAY\t$SHOW\t$START24" >> schedule.tsv
            SHOW=""
        fi
    fi
done < "$INPUT"

# Output
column -ts $'\t' schedule.tsv
