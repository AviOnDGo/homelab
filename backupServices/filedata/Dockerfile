FROM alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

RUN apk add --no-cache rclone curl bash findutils gnupg tar zstd

COPY --chmod=755 filedata-backup-script.sh /usr/local/bin/backup-script.sh
COPY --chmod=755 configure-rclone.sh /usr/local/bin/configure-rclone.sh
