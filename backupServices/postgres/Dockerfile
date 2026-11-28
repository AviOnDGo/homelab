FROM postgres:19.0-alpine@sha256:cac45fb483caee3668946088a1c0532db89d5285c28dbfeac889b4068296e06f

RUN apk add --no-cache rclone curl bash findutils gnupg zstd

COPY db-backup-script.sh /usr/local/bin/backup-script.sh
RUN chmod 755 /usr/local/bin/backup-script.sh
