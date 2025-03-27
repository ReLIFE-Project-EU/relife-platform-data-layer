# ReLIFE Example Stack

An example stack demonstrating how all components of the ReLIFE platform fit together.

## Configuration

> [!IMPORTANT]
> This project uses `host.docker.internal` to access the host transparently from both inside and outside the Docker containers. If you're on Linux, please note that `host.docker.internal` is not configured inside Docker containers by default. Additionally, to enable this hostname from outside containers (i.e., from the host itself), you should add an entry to your `/etc/hosts` file to map `host.docker.internal` to `127.0.0.1`.

The configuration is defined via dotenv files, specifically there's an `.env.default` file that contains the default values. You may create a custom `.env` file to override the default values.

Technically, you should only need to do a few things:

* Once you've configured the Keycloak realm, update the value of `KEYCLOAK_SUPABASE_CLIENT_SECRET` to be the client secret of the Supabase client in the Keycloak realm indicated by the `KEYCLOAK_REALM` parameter.
* Double check that `host.docker.internal` resolves to your local machine from both inside and outside the Docker containers. You may need to add an entry to your `/etc/hosts` file to ensure this is the case.

## Deployment

First, you need to create the dotenv file that will contain the JWT tokens for Supabase anonymous and service role access:

```console
task gen-keys
```

Then, you can deploy the central services (Supabase and Keycloak) using the following commands:

```console
task central:supabase-deploy
```

Wait for a few seconds for the Supabase services to be ready. Then, you can deploy the Keycloak service:

```console
task central:keycloak-deploy
```

### Configuring the Keycloak Realm

Now that the Keycloak service is running, you need to configure the Keycloak realm and the Supabase Keycloak client for social login (OAuth). Please refer to the following guide for instructions on how to do this:

[Supabase Docs: Login with Keycloak](https://supabase.com/docs/guides/auth/social-login/auth-keycloak)

You'll need to access the Keycloak admin console at `http://localhost:${KEYCLOAK_PORT}/admin/`. The port is 8080 by default. The admin credentials are specified by `KEYCLOAK_ADMIN_USER` and `KEYCLOAK_ADMIN_PASSWORD` (both default to `keycloak`).

During the creation of the Supabase Keycloak client, you'll need to specify what Keycloak refers to as the _Login Settings_:

| Setting Name                    | Description                                                                          | Recommended Value                                        |
| ------------------------------- | ------------------------------------------------------------------------------------ | -------------------------------------------------------- |
| Root URL                        | The base URL where your application is hosted                                        | `http://localhost:10100`                                 |
| Home URL                        | Default URL to use when the auth server needs to redirect or link back to the client | `http://localhost:10100`                                 |
| Valid Redirect URIs             | Allowed URLs where Keycloak can redirect after authentication                        | `http://localhost:10100/*` and `http://localhost:8000/*` |
| Valid Post Logout Redirect URIs | Allowed URLs where Keycloak can redirect after logout                                | `+`                                                      |
| Web Origins                     | Allowed origins for CORS requests to Keycloak                                        | `+`                                                      |

> [!TIP]
> * `http://localhost:10100` is the URL of the open access tool web application
> * `http://localhost:8000` is the URL of the Supabase API gateway

Then, copy the client secret found in the _Credentials_ section of the client configuration. Copy it to the `.env` file as `KEYCLOAK_SUPABASE_CLIENT_SECRET`. For example:

```dotenv
KEYCLOAK_SUPABASE_CLIENT_SECRET=6VMhsLstslaAY6DogeOsgT9odH1y64OE
```

Create a new user in the Keycloak realm and make sure to set a password for the user. This will be used to authenticate in the open access tool web application.

> [!NOTE]
> Make sure to check "Email Verified" for the user.

Finally, once the `.env` file has been updated with the Supabase client secret, you need to redeploy the Supabase services:

```console
task central:supabase-deploy
```

## Run Open Access Tool Web Application

You can start the open access tool web application in development mode by running the following command:

```console
task dev-tool-first
```

If you look at the source code in `open-access-tool-01`, you can see how to organize the code, create the Supabase client, and use it to log in and log out users via the Keycloak provider.

## TODOs

* Explain that the _service accounts roles_ option needs to be enabled in the Keycloak client settings for backend APIs to use client credentials grants.
* Document that each backend component should have its own dedicated Keycloak client.
* Explain that backend API clients need the realm-management client role "realm-admin" assigned to their service account to be able to check user role mappings.
