FROM node:20-alpine AS builder

ARG VITE_SUPABASE_URL=http://host.docker.internal:8000
ARG VITE_SUPABASE_ANON_KEY
ARG VITE_KEYCLOAK_CLIENT_ID=supabase
ARG VITE_KEYCLOAK_URL=http://host.docker.internal:8000
ARG VITE_KEYCLOAK_REALM=relife

ENV VITE_SUPABASE_URL=${VITE_SUPABASE_URL}
ENV VITE_SUPABASE_ANON_KEY=${VITE_SUPABASE_ANON_KEY}
ENV VITE_KEYCLOAK_CLIENT_ID=${VITE_KEYCLOAK_CLIENT_ID}
ENV VITE_KEYCLOAK_URL=${VITE_KEYCLOAK_URL}
ENV VITE_KEYCLOAK_REALM=${VITE_KEYCLOAK_REALM}

WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM caddy:2-alpine

RUN apk add --no-cache curl
COPY --from=builder /app/dist /usr/share/caddy
COPY Caddyfile /etc/caddy/Caddyfile
EXPOSE 80
ENV API_URL=http://api:9090
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"] 