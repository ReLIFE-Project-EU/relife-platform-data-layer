# ReLIFE Example Stack

An example stack demonstrating how all components of the ReLIFE platform fit together.

## Enabling Keycloak for Social Login (OAuth) in Supabase

[Guide to configure Keycloak for Social Login (OAuth) in Supabase](https://supabase.com/docs/guides/auth/social-login/auth-keycloak).

[Configure the external authentication provider to enable Keycloak login](https://github.com/supabase/auth?tab=readme-ov-file#external-authentication-providers).

Example environment variables for the auth service in the Compose file:

```
GOTRUE_EXTERNAL_KEYCLOAK_ENABLED: true
GOTRUE_EXTERNAL_KEYCLOAK_CLIENT_ID: Supabase
GOTRUE_EXTERNAL_KEYCLOAK_SECRET: aGeG4sCQkuHiP38msx1T1Q48auS781Cf
GOTRUE_EXTERNAL_KEYCLOAK_REDIRECT_URI: http://localhost:10100/auth/callback
GOTRUE_EXTERNAL_KEYCLOAK_URL: http://localhost:8080/realms/Test
```