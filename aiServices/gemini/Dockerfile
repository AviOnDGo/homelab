FROM node:26-bookworm-slim

RUN apt-get update \
    && apt-get install --yes --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

RUN npm install --global @google/gemini-cli@0.65.0 \
    && npm cache clean --force

WORKDIR /workspace
USER node

ENTRYPOINT ["gemini"]
