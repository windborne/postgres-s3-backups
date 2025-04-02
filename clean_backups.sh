#!/bin/bash

set -e

# Configuration
RETENTION_DAYS=30                  # Keep backups newer than this many days
KEEP_DAYS=(1 7 15 22 28)           # Days of month to preserve regardless of age

# Make sure AWS environment variables are properly passed
# Uncomment and set these if they're not already in your environment
# export AWS_ACCESS_KEY_ID="your-access-key"
# export AWS_SECRET_ACCESS_KEY="your-secret-key"
# export AWS_REGION="your-region"

# Debug: Print the AWS profile and bucket information
echo "Using AWS profile: $(aws configure list-profiles | grep '*' || echo 'default')"
echo "Targeting bucket: $S3_BUCKET_NAME"

echo "Starting backup cleanup process..."

# Get current date for calculations
CURRENT_DATE=$(date +%s)

# List all backup files in the bucket
echo "Listing all backup files..."
echo "Running: aws s3 ls s3://$S3_BUCKET_NAME/db_backups/ --recursive"
S3_FILES=$(aws s3 ls "s3://$S3_BUCKET_NAME/db_backups/" --recursive)

# Debug: Show the first few files found or error
if [ $? -ne 0 ]; then
    echo "Error listing files. Check your AWS credentials and permissions."
    exit 1
fi


# Filter only backup files
echo "Filtering for backup files..."
S3_FILES=$(echo "$S3_FILES" | grep -E "backup-.*\.sql\.gz$" || echo "")

# Process each file
echo "Processing backup files..."
while read -r line; do
    # Skip empty lines
    [ -z "$line" ] && continue

    # Extract the date, time, and full path from the S3 listing
    S3_DATE=$(echo "$line" | awk '{print $1}')
    S3_TIME=$(echo "$line" | awk '{print $2}')
    S3_FILE=$(echo "$line" | awk '{print $4}')

    # Extract year, month, and day from the file path
    if [[ $S3_FILE =~ db_backups/([0-9]{4})/([0-9]{2})/([0-9]{2})/backup- ]]; then
        YEAR=${BASH_REMATCH[1]}
        MONTH=${BASH_REMATCH[2]}
        DAY=${BASH_REMATCH[3]}

        # Remove leading zero from day for numeric comparison
        # This handles the case where DAY has a leading zero
        DAY_NUM=$((10#$DAY))

        # Create a date string for the backup file and convert to seconds since epoch
        # macOS-compatible date conversion
        if [[ "$OSTYPE" == "darwin"* ]]; then
            # macOS date command
            FILE_DATE=$(date -j -f "%Y-%m-%d" "$YEAR-$MONTH-$DAY" +%s)
        else
            # GNU/Linux date command
            FILE_DATE=$(date -d "$YEAR-$MONTH-$DAY" +%s)
        fi

        # Calculate age in days
        AGE_DAYS=$(( (CURRENT_DATE - FILE_DATE) / 86400 ))

        # Check if the file is older than retention period and not on a keep day
        if [ $AGE_DAYS -gt $RETENTION_DAYS ]; then
            KEEP_THIS=false

            # Check if this day is in our list of days to keep
            for KEEP_DAY in "${KEEP_DAYS[@]}"; do
                if [ $DAY_NUM -eq $KEEP_DAY ]; then
                    KEEP_THIS=true
                    break
                fi
            done

            if [ "$KEEP_THIS" = false ]; then
                echo "Deleting: $S3_FILE (Age: $AGE_DAYS days)"
                aws s3 rm "s3://$S3_BUCKET_NAME/$S3_FILE"
            else
                echo "Preserving: $S3_FILE (Age: $AGE_DAYS days, Day $DAY_NUM is marked for retention)"
            fi
        else
            echo "Preserving: $S3_FILE (Age: $AGE_DAYS days, within retention period)"
        fi
    else
        echo "Skipping: $S3_FILE (Doesn't match expected format)"
    fi
done <<< "$S3_FILES"

echo "Backup cleanup completed!"
