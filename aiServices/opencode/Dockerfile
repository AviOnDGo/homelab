FROM node:22-bookworm-slim

ARG OPENCODE_VERSION=1.19.4

RUN apt-get update \
    && apt-get install --no-install-recommends -y bash ca-certificates curl git \
    && npm install --global "opencode-ai@${OPENCODE_VERSION}" \
    && rm -rf /var/lib/apt/lists/* \
    && install -d /home/node/.local/share/opencode /home/node/.local/state \
        /home/node/.config/opencode /home/node/.cache \
    && chown -R node:node /home/node/.local /home/node/.config /home/node/.cache

COPY entrypoint.sh /usr/local/bin/container-entrypoint
RUN chmod 755 /usr/local/bin/container-entrypoint

ENV HOME=/home/node
WORKDIR /workspace
USER node

ENTRYPOINT ["container-entrypoint"]
