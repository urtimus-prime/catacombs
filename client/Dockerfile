FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_RPC_URL
ARG VITE_TORII_URL
ARG VITE_CHAIN
RUN npx vite build

FROM nginx:alpine
LABEL org.opencontainers.image.source="https://github.com/urtimus-prime/catacombs"
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
