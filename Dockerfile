ARG POSTGRES_VERSION
FROM postgres:${POSTGRES_VERSION}

RUN apt-get update && apt-get install -y awscli

WORKDIR /scripts

# Copy your scripts into the container
COPY backup.sh .
COPY restore_backup.sh .
COPY incremental_copy.sh .

# Ensure the scripts have execution permissions
RUN chmod +x backup.sh restore_backup.sh incremental_copy.sh

# Set the entrypoint to your backup script
ENTRYPOINT [ "/scripts/backup.sh" ]