FROM oven/bun:1 AS build
WORKDIR /app
COPY reference/explorer/package.json reference/explorer/bun.lock ./
RUN bun install --frozen-lockfile
COPY reference/explorer/ .
ARG VITE_RPC_URL
RUN bun run build

FROM nginx:alpine
LABEL org.opencontainers.image.source="https://github.com/urtimus-prime/catacombs"
COPY --from=build /app/dist /usr/share/nginx/html
COPY explorer/nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
