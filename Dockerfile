# ----------------------------
# Global ARGs
# ----------------------------
ARG DATABASE_TYPE
ARG BASE_PATH
ARG NODE_OPTIONS

# ----------------------------
# Install dependencies
# ----------------------------
FROM node:22-alpine AS deps

RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN npm install -g pnpm
RUN pnpm install --frozen-lockfile

# ----------------------------
# Build app
# ----------------------------
FROM node:22-alpine AS builder

WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

ARG DATABASE_TYPE
ARG BASE_PATH

ENV DATABASE_TYPE=$DATABASE_TYPE
ENV BASE_PATH=$BASE_PATH
ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build-docker

# ----------------------------
# Final runtime image
# ----------------------------
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV HOSTNAME=0.0.0.0
ENV PORT=3000

ARG NODE_OPTIONS
ENV NODE_OPTIONS=$NODE_OPTIONS

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs
RUN npm install -g pnpm
RUN set -x && apk add --no-cache curl

# Add script deps
RUN pnpm add npm-run-all dotenv prisma@6.7.0
RUN chown -R nextjs:nodejs node_modules/.pnpm/

# Copy built output
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/scripts ./scripts
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

RUN mv ./.next/routes-manifest.json ./.next/routes-manifest-orig.json

USER nextjs
EXPOSE 3000

CMD ["pnpm", "start-docker"]
