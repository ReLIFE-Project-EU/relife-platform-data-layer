# ReLIFE Example Stack

An example stack demonstrating how all components of the ReLIFE platform fit together.

## Configuration

> [!IMPORTANT]
> This project's default configuration uses `host.docker.internal` to access the host transparently from both inside and outside the Docker containers. If you're on Linux, please note that `host.docker.internal` is not configured inside Docker containers by default. Additionally, to enable this hostname from outside containers (i.e., from the host itself), you should add an entry to your `/etc/hosts` file to map `host.docker.internal` to `127.0.0.1`.

The configuration is defined via dotenv files, specifically there's an `.env.default` file that contains the default values. You may create a custom `.env` file to override the default values.

## Deployment

First, you need to create the dotenv file that will contain the JWT tokens for Supabase anonymous and service role access:

```console
task gen-keys
```

Then, you can deploy the central services (Supabase and Keycloak) using the following command:

```console
task central:deploy
```

### Configuring the Keycloak Realm

Now that the Keycloak service is running, you need to configure the Keycloak realm for authentication.

Access the Keycloak admin console at `http://localhost:${KEYCLOAK_PORT}/admin/` (default port is 8080). Log in using the admin credentials specified in `KEYCLOAK_ADMIN_USER` and `KEYCLOAK_ADMIN_PASSWORD` (both default to `keycloak`).

Follow these steps to configure the realm:

1. Create a new realm named `relife`.
2. In the _Clients_ section, click _Import client_ and import all client configurations from the JSON files in the `central-services/keycloak-config` directory.
3. For the `service` client, add the `realm-admin` role under the _Service accounts roles_ section.
4. Create a new user in the realm and set their password—this user will be used to test authentication in the open access tool web applications. Make sure to enable the _Email Verified_ setting for this user.

For security, it's recommended to regenerate the client secrets. You can do this in the _Credentials_ section of each client's configuration. Copy the new secrets to your `.env` file to update the appropriate environment variables. For example:

```dotenv
KEYCLOAK_SUPABASE_CLIENT_SECRET=6VMhsLstslaAY6DogeOsgT9odH1y64OE
KEYCLOAK_RELIFE_SERVICE_CLIENT_SECRET=VnCufvj4jSbd6gS5tadQLT0oEyliGyVU
```

If you regenerate the secrets, you need to redeploy Supabase:

```console
task central:supabase-deploy
```

## Development

You can start both the service HTTP API and the open access tool web UI in development mode using the following commands:

```console
task dev-service-api
```

```console
task dev-webui
```

The `open-access-tool` directory contains example code demonstrating how to:

- Structure a React application with Supabase authentication
- Initialize and configure the Supabase client
- Implement user login/logout flows using Keycloak as the authentication provider
