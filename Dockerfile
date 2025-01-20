FROM node:20-slim AS deps
WORKDIR /app

# Install dependencies first for better caching
COPY package.json package-lock.json* ./
RUN \
  if [ -f package-lock.json ]; then npm ci; \
  else npm install; \
  fi

FROM node:20-slim AS builder
WORKDIR /app

# Install build essentials
RUN apt-get update && apt-get install -y \
    build-essential \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Copy dependencies and source code
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Copy and prepare environment script
RUN ENV_FILE=".env.local" && > "$ENV_FILE" && for var in $(env | cut -d= -f1); do if [[ $var == NEXT_* ]] || [[ $var == API_* ]] || [[ $var == DB_* ]] || [[ $var == CUSTOM_* ]]; then echo "$var=${!var}" >> "$ENV_FILE" && echo "Added $var to environment"; fi; done && echo "Generated .env.local contents:" && cat "$ENV_FILE"

# Build the application
RUN npm run build

FROM node:20-slim AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

USER nextjs
EXPOSE 3000

CMD ["npm", "start"]
