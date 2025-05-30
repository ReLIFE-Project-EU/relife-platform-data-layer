# Open Access Tool Template

A minimal example that demonstrates how to configure a Vite + React + Mantine web application for integration with ReLIFE's backend services. The application uses Supabase as the data layer and Keycloak for identity management.

This example demonstrates Keycloak authentication through a Supabase client. Users in Keycloak can log in while leveraging Supabase libraries for simplified data handling.

## Features

- Authentication with Keycloak via Supabase
- User profile and role information
- File storage access
- Report requests
- User management
- Integration with the example ReLIFE Service API

## Configuration Architecture

This application follows a centralized configuration pattern to maximize clarity and maintainability:

### Configuration Files

- **`src/config.js`**: Central file that contains all configuration settings grouped by functionality
- **`src/auth.js`**: Authentication utilities that use the centralized configuration
- **`vite.config.js`**: Development server configuration

### Environment Variables

All configuration is driven by environment variables with sensible defaults:

#### Configuration Variables

| Category              | Variable                    | Description                                           | Default Value           |
| --------------------- | --------------------------- | ----------------------------------------------------- | ----------------------- |
| **Supabase**          | `VITE_SUPABASE_URL`         | URL of the Supabase instance                          | `http://localhost:8000` |
|                       | `VITE_SUPABASE_ANON_KEY`    | Anonymous API key for Supabase                        | -                       |
| **Keycloak**          | `VITE_KEYCLOAK_URL`         | URL of the Keycloak instance                          | -                       |
|                       | `VITE_KEYCLOAK_REALM`       | Keycloak realm name                                   | -                       |
|                       | `VITE_KEYCLOAK_CLIENT_ID`   | Client ID for the application in Keycloak             | -                       |
| **API**               | `VITE_SERVICE_API_URL`      | URL for the service API                               | `/api`                  |
| **API (Development)** | `VITE_DEV_SERVICE_API_HOST` | Host for the service API to be proxied in development | `localhost`             |
|                       | `VITE_DEV_SERVICE_API_PORT` | Port for the service API to be proxied in development | `9090`                  |

### API URL Configuration

There are two different environment variables used for API configuration:

1. **`VITE_SERVICE_API_URL`**: Used by the frontend application (React) to determine the API endpoint path. This is typically set to `/api` and is used in the frontend code to make API requests.

2. **`API_URL`**: Used by the Caddy server in production to determine where to proxy API requests. This points to the actual API service location (e.g., `http://api:9090`). This variable is only used in the Dockerfile and Caddyfile and is not exposed to the frontend code.

The workflow is:

- Frontend makes requests to `VITE_SERVICE_API_URL` (e.g., `/api/users`)
- Caddy intercepts these requests and forwards them to `API_URL` (e.g., `http://api:9090/users`)

## Local Development

To start the development server:

```bash
npm install
npm run dev
```
