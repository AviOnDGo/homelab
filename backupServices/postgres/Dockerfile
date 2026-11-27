FROM postgres:18.7-alpine@sha256:0115267ab5a509022df9319c77be365cef335adb71556c75f60f5360ee247e71

RUN apk add --no-cache rclone curl bash findutils gnupg zstd

COPY --chmod=755 db-backup-script.sh /usr/local/bin/backup-script.sh
