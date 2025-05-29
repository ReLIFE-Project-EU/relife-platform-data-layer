FROM node:20-alpine AS builder

# Supabase Configuration
ARG VITE_SUPABASE_URL=http://host.docker.internal:8000
ARG VITE_SUPABASE_ANON_KEY

# Keycloak Configuration
ARG VITE_KEYCLOAK_URL=http://host.docker.internal:8000
ARG VITE_KEYCLOAK_REALM=relife
ARG VITE_KEYCLOAK_CLIENT_ID=supabase

# API Configuration
# VITE_SERVICE_API_URL is used by the frontend to determine the API endpoint path
# This is typically "/api" which is then handled by Caddy's reverse proxy
ARG VITE_SERVICE_API_URL=/api

# Set environment variables from build arguments
# Supabase
ENV VITE_SUPABASE_URL=${VITE_SUPABASE_URL}
ENV VITE_SUPABASE_ANON_KEY=${VITE_SUPABASE_ANON_KEY}

# Keycloak
ENV VITE_KEYCLOAK_URL=${VITE_KEYCLOAK_URL}
ENV VITE_KEYCLOAK_REALM=${VITE_KEYCLOAK_REALM}
ENV VITE_KEYCLOAK_CLIENT_ID=${VITE_KEYCLOAK_CLIENT_ID}

# API
ENV VITE_SERVICE_API_URL=${VITE_SERVICE_API_URL}

# Build the application
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Serve with Caddy
FROM caddy:2-alpine

RUN apk add --no-cache curl
COPY --from=builder /app/dist /usr/share/caddy
COPY Caddyfile /etc/caddy/Caddyfile
EXPOSE 80
# API_URL is used by Caddy to determine where to proxy the API requests
# This points to the actual API service location
ENV API_URL=http://api:9090
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile"]
