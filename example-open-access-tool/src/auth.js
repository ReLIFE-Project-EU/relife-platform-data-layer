import { createClient } from "@supabase/supabase-js";
import {
  API_CONFIG,
  KEYCLOAK_CONFIG,
  SUPABASE_CLIENT_CONFIG,
  SUPABASE_CONFIG,
  getKeycloakLogoutUrl,
} from "./config";

export { getKeycloakLogoutUrl };

// Create Supabase client using centralized configuration
export function getClient() {
  return createClient(
    SUPABASE_CONFIG.url,
    SUPABASE_CONFIG.anonKey,
    SUPABASE_CLIENT_CONFIG
  );
}

// Helper functions to access configuration values
export function getSupabaseUrl() {
  return SUPABASE_CONFIG.url;
}

export function getServiceApiUrl() {
  return API_CONFIG.url;
}

export function getKeycloakUrl() {
  return KEYCLOAK_CONFIG.url;
}

export function getKeycloakRealm() {
  return KEYCLOAK_CONFIG.realm;
}

export function getKeycloakClientId() {
  return KEYCLOAK_CONFIG.clientId;
}

export async function signInWithKeycloak({ supabase }) {
  await supabase.auth.signInWithOAuth({
    provider: "keycloak",
    options: {
      scopes: "openid",
    },
  });
}

export const supabase = getClient();
