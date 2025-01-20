# syntax=docker.io/docker/dockerfile:1

FROM node:18-alpine AS base

# Install dependencies only when needed
FROM base AS deps
# Check https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine to understand why libc6-compat might be needed.
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Install dependencies based on the preferred package manager
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* .npmrc* ./
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile; \
  else echo "Lockfile not found." && exit 1; \
  fi


# Build stage with completely dynamic environment generation
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Next.js collects completely anonymous telemetry data about general usage.
# Learn more here: https://nextjs.org/telemetry
# Uncomment the following line in case you want to disable telemetry during the build.
# ENV NEXT_TELEMETRY_DISABLED=1

RUN \
  # First determine which package manager to use
  if [ -f yarn.lock ]; then \
    PACKAGE_MANAGER="yarn"; \
  elif [ -f package-lock.json ]; then \
    PACKAGE_MANAGER="npm"; \
  elif [ -f pnpm-lock.yaml ]; then \
    corepack enable pnpm && PACKAGE_MANAGER="pnpm"; \
  else \
    echo "Lockfile not found." && exit 1; \
  fi && \
  # Then check Next.js configuration and run appropriate build command
  if grep -q '"output": "standalone"' next.config.js; then \
    echo "Standalone output detected"; \
    $PACKAGE_MANAGER run build; \
  elif grep -q '"output": "export"' next.config.js; then \
    echo "Static export detected"; \
    $PACKAGE_MANAGER run build && $PACKAGE_MANAGER run export; \
  else \
    echo "Default build detected"; \
    $PACKAGE_MANAGER run build; \
  fi

# Production stage with multiple output handling
FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
# Uncomment the following line in case you want to disable telemetry during runtime.
# ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public

# Automatically leverage output traces to reduce image size
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT=3000

# server.js is created by next build from the standalone output
# https://nextjs.org/docs/pages/api-reference/config/next-config-js/output
ENV HOSTNAME="0.0.0.0"
CMD ["node", "server.js"]
