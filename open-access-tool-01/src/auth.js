import { createClient } from "@supabase/supabase-js";

export function getSupabaseUrl() {
  return import.meta.env.VITE_SUPABASE_URL || "http://localhost:8000";
}

export function getClient() {
  const supabaseUrl = getSupabaseUrl();
  const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
  return createClient(supabaseUrl, supabaseKey);
}

export function getKeycloakUrl() {
  return import.meta.env.VITE_KEYCLOAK_URL;
}

export function getKeycloakRealm() {
  return import.meta.env.VITE_KEYCLOAK_REALM;
}

export function getKeycloakClientId() {
  return import.meta.env.VITE_KEYCLOAK_CLIENT_ID;
}

export function getKeycloakLogoutUrl() {
  const keycloakUrl = getKeycloakUrl();
  const keycloakRealm = getKeycloakRealm();
  const clientId = getKeycloakClientId();
  const redirectUri = window.location.origin;

  if (!keycloakUrl || !keycloakRealm || !clientId) {
    console.warn("Keycloak URL or realm not configured.");
    return;
  }

  const logoutUrl = new URL(
    `${keycloakUrl}/realms/${keycloakRealm}/protocol/openid-connect/logout`
  );

  logoutUrl.searchParams.append("client_id", clientId);
  logoutUrl.searchParams.append("post_logout_redirect_uri", redirectUri);

  return logoutUrl.toString();
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
