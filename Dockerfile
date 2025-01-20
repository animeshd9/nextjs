FROM node:20-slim AS base
RUN apt-get update && apt-get install -y \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app

# Dependencies stage
FROM base AS deps
COPY package.json package-lock.json* ./
RUN \
  if [ -f package-lock.json ]; then npm ci; \
  else npm install; \
  fi

# Build stage with completely dynamic environment generation
FROM base AS builder
RUN apt-get update && apt-get install -y \
    build-essential \
    python3 \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Copy node modules and application code
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Detect project configuration
RUN \
  if grep -q '"output": "standalone"' next.config.js; then \
    echo "Standalone output detected"; \
    npm run build; \
  elif grep -q '"output": "export"' next.config.js; then \
    echo "Static export detected"; \
    npm run build && npm run export; \
  else \
    echo "Default build detected"; \
    npm run build; \
  fi

# Production stage with multiple output handling
FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy different build artifacts based on project configuration
COPY --from=builder /app/public ./public
# Standalone output
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./standalone || true
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./standalone/.next/static || true
# Static export output
COPY --from=builder --chown=nextjs:nodejs /app/out ./out || true
# Default Next.js build
COPY --from=builder --chown=nextjs:nodejs /app/.next ./next || true

USER nextjs
EXPOSE 3000
ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

# Conditional CMD based on project configuration
CMD \
  if [ -f "./standalone/server.js" ]; then \
    node ./standalone/server.js; \
  elif [ -d "./out" ]; then \
    npx serve@latest ./out -p 3000; \
  else \
    npm run start; \
  fi 
