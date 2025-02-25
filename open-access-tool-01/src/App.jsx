import {
  Button,
  Code,
  Container,
  Group,
  Image,
  MantineProvider,
  Paper,
  Stack,
  Table,
  Text,
  Title,
} from "@mantine/core";
import "@mantine/core/styles.css";
import { createClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";
import relifeLogo from "./assets/relife-logo.png";

function getSupabaseUrl() {
  return import.meta.env.VITE_SUPABASE_URL || "http://localhost:8000";
}

function getClient() {
  const supabaseUrl = getSupabaseUrl();
  const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY;
  return createClient(supabaseUrl, supabaseKey);
}

function getKeycloakUrl() {
  return import.meta.env.VITE_KEYCLOAK_URL;
}

function getKeycloakRealm() {
  return import.meta.env.VITE_KEYCLOAK_REALM;
}

function getKeycloakClientId() {
  return import.meta.env.VITE_KEYCLOAK_CLIENT_ID;
}

function getKeycloakLogoutUrl() {
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

async function signInWithKeycloak({ supabase }) {
  await supabase.auth.signInWithOAuth({
    provider: "keycloak",
    options: {
      scopes: "openid",
    },
  });
}

const supabase = getClient();

function App() {
  const [session, setSession] = useState(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      console.debug("session", session);
      setSession(session);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      console.debug("session", session);
      setSession(session);
    });

    return () => subscription.unsubscribe();
  }, []);

  const handleLogin = async () => {
    await signInWithKeycloak({ supabase });
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();

    const logoutUrl = getKeycloakLogoutUrl();

    if (logoutUrl) {
      window.location.assign(logoutUrl.toString());
    }
  };

  return (
    <MantineProvider>
      <Container size="sm" py="xl">
        <Stack spacing="xl" justify="center">
          <Group align="center" justify="center">
            <Image src={relifeLogo} fit="contain" w={200} />
          </Group>

          <Title order={1}>Open Access Tool Template</Title>

          <Title order={3} c="dimmed">
            Authentication with Supabase using Keycloak as provider
          </Title>

          <Table>
            <Table.Tbody>
              {getSupabaseUrl() && (
                <Table.Tr>
                  <Table.Td c="dimmed">Supabase URL</Table.Td>
                  <Table.Td>
                    <Code>{getSupabaseUrl()}</Code>
                  </Table.Td>
                </Table.Tr>
              )}
              {getKeycloakUrl() && (
                <Table.Tr>
                  <Table.Td c="dimmed">Keycloak URL</Table.Td>
                  <Table.Td>
                    <Code>{getKeycloakUrl()}</Code>
                  </Table.Td>
                </Table.Tr>
              )}
              {getKeycloakRealm() && (
                <Table.Tr>
                  <Table.Td c="dimmed">Keycloak Realm</Table.Td>
                  <Table.Td>
                    <Code>{getKeycloakRealm()}</Code>
                  </Table.Td>
                </Table.Tr>
              )}
              {getKeycloakClientId() && (
                <Table.Tr>
                  <Table.Td c="dimmed">Keycloak Client ID</Table.Td>
                  <Table.Td>
                    <Code>{getKeycloakClientId()}</Code>
                  </Table.Td>
                </Table.Tr>
              )}
            </Table.Tbody>
          </Table>

          <Text>
            This is a minimal example that shows how to configure a Vite + React
            + Mantine web application for integration with ReLIFE&apos;s backend
            services, which are based on Supabase as the data layer and Keycloak
            for identity management.
          </Text>

          <Text>
            This example demonstrates Keycloak authentication through a Supabase
            client. Users in Keycloak can log in while leveraging Supabase
            libraries for simplified data handling.
          </Text>

          {!session ? (
            <Button onClick={handleLogin} variant="filled">
              Sign in with Supabase via Keycloak
            </Button>
          ) : (
            <Paper shadow="sm" p="md" withBorder>
              <Text>
                Signed in as: <Code>{session.user.email}</Code>
              </Text>
              <Button
                fullWidth
                onClick={handleLogout}
                variant="light"
                color="red"
                mt="sm"
              >
                Sign Out
              </Button>
            </Paper>
          )}
        </Stack>
      </Container>
    </MantineProvider>
  );
}

export default App;
