
# syntax=docker/dockerfile:1

# Multi-stage build for Next.js + Prisma
# File is named "dockerfile" (lowercase). Build with: docker build -f dockerfile .

FROM node:20-bookworm-slim AS base
WORKDIR /app

# Prisma engines on Debian need OpenSSL + certs
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates openssl \
	&& rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1


FROM base AS deps
ENV NODE_ENV=development

# Install dependencies first for better layer caching.
COPY package.json package-lock.json ./

# Prisma generate runs on postinstall, so schema must exist during install.
COPY prisma ./prisma

RUN npm ci


FROM base AS builder
ENV NODE_ENV=production

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Ensure Prisma Client is generated (postinstall should handle it, but keep explicit for CI/docker).
RUN npx prisma generate

RUN npm run build

# Remove devDependencies but keep the generated Prisma client.
RUN npm prune --omit=dev


FROM base AS runner
ENV NODE_ENV=production
ENV PORT=3000

# Optional but helps some hosting environments.
ENV HOSTNAME=0.0.0.0

COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public

# Keep Prisma folder available (useful for migrations/debug; remove if you prefer smaller images).
COPY --from=builder /app/prisma ./prisma

EXPOSE 3000

# Force binding to all interfaces for Docker.
CMD ["node", "node_modules/next/dist/bin/next", "start", "-H", "0.0.0.0", "-p", "3000"]
