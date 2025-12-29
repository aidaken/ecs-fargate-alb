FROM node:20-alpine
WORKDIR /app
COPY app/package.json /app/package.json
COPY app/server.js /app/server.js
ENV PORT=3000
EXPOSE 3000
CMD ["node", "server.js"]

