# hindsight WhatsApp bot. Login (auth/) and chat state (state/) live in /data (a volume),
# so a redeploy doesn't log the bot out.
FROM node:24-slim
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY bot.js convert.js ./
WORKDIR /data
CMD ["node", "/app/bot.js"]
