/**
 * Central configuration file for the application
 * All environment variables and configuration settings are defined here
 */

// Supabase Configuration
export const SUPABASE_CONFIG = {
  url: import.meta.env.VITE_SUPABASE_URL || "http://localhost:8000",
  anonKey: import.meta.env.VITE_SUPABASE_ANON_KEY,
};

// Keycloak Configuration
export const KEYCLOAK_CONFIG = {
  url: import.meta.env.VITE_KEYCLOAK_URL,
  realm: import.meta.env.VITE_KEYCLOAK_REALM,
  clientId: import.meta.env.VITE_KEYCLOAK_CLIENT_ID,
};

// API Configuration
export const API_CONFIG = {
  url: import.meta.env.VITE_SERVICE_API_URL || "/api",
};

// App Configuration
export const APP_CONFIG = {
  name: "Open Access Tool Template",
  description: "Authentication with Supabase using Keycloak as provider",
};

// Build helper functions for generating URLs and other derived config values
export function getKeycloakLogoutUrl() {
  const { url, realm, clientId } = KEYCLOAK_CONFIG;
  const redirectUri = window.location.origin;

  if (!url || !realm || !clientId) {
    console.warn("Keycloak URL, realm, or client ID not configured.");
    return;
  }

  const logoutUrl = new URL(
    `${url}/realms/${realm}/protocol/openid-connect/logout`
  );

  logoutUrl.searchParams.append("client_id", clientId);
  logoutUrl.searchParams.append("post_logout_redirect_uri", redirectUri);

  return logoutUrl.toString();
}

// Create and export the Supabase client configuration
export const SUPABASE_CLIENT_CONFIG = {
  auth: {
    flowType: "implicit",
    autoRefreshToken: true,
  },
};
