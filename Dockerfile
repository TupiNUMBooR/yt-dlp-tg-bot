FROM node:23-alpine

# Install necessary packages for gallery-dl and yt-dlp
RUN apk add --no-cache yt-dlp

# Create app directory
WORKDIR /app

# Copy bot code
COPY . .

# Install node modules
RUN npm install

# Start bot with environment variables
CMD ["node", "bot.js"]
