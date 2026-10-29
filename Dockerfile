# Official Node.js 22 image on Alpine Linux: small and maintained
FROM node:22-alpine

# Every following instruction runs inside /app
WORKDIR /app
ENV NODE_ENV=production

# Copy only the dependency manifests first: this layer stays cached
# until package.json or package-lock.json change
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Then the application code, which changes often
COPY src ./src

# A data directory the unprivileged 'node' user can write to
RUN mkdir -p /app/data && chown node:node /app/data

# Version label; CI passes the Git commit SHA.
# Empty means the app falls back to the version in package.json.
ARG APP_VERSION=""
ENV APP_VERSION=${APP_VERSION}

# Never run as root inside the container
USER node
EXPOSE 3000
CMD ["node", "src/server.js"]
