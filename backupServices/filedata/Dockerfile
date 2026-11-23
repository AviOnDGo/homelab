FROM alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf

RUN apk add --no-cache rclone curl bash findutils gnupg tar zstd

COPY --chmod=755 filedata-backup-script.sh /usr/local/bin/backup-script.sh
COPY --chmod=755 configure-rclone.sh /usr/local/bin/configure-rclone.sh
