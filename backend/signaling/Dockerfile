FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY config/ ./config/
COPY src/ ./src/

# Drop root: node:20-alpine ships an unprivileged `node` user. An RCE in the
# process should not run as UID 0 in-container.
USER node

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:8001/health || exit 1

CMD ["node", "src/server.js"]
