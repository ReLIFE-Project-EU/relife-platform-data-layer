import {
  Button,
  Card,
  Code,
  Container,
  Group,
  Image,
  Stack,
  Table,
  Text,
  ThemeIcon,
  Title,
  rem,
} from "@mantine/core";
import "@mantine/core/styles.css";
import { IconBrandSupabase, IconKey, IconUser } from "@tabler/icons-react";
import { useCallback, useEffect } from "react";
import relifeLogo from "./assets/relife-logo.png";
import {
  getKeycloakClientId,
  getKeycloakLogoutUrl,
  getKeycloakRealm,
  getKeycloakUrl,
  getSupabaseUrl,
  signInWithKeycloak,
  supabase,
} from "./auth";
import ReportRequests from "./components/ReportRequests";
import { useSupabaseSession, useWhoami } from "./hooks";

function App() {
  const session = useSupabaseSession();
  const { whoami, fullName } = useWhoami(session);

  useEffect(() => {
    console.debug("Supabase session", session);
  }, [session]);

  useEffect(() => {
    console.debug("Whoami", whoami);
  }, [whoami]);

  const handleLogin = useCallback(async () => {
    await signInWithKeycloak({ supabase });
  }, []);

  const handleLogout = useCallback(async () => {
    await supabase.auth.signOut();
    const logoutUrl = getKeycloakLogoutUrl();

    if (logoutUrl) {
      window.location.assign(logoutUrl.toString());
    }
  }, []);

  return (
    <Container size="sm" py="xl">
      <Stack spacing="xl" justify="center">
        <Group align="center" justify="center">
          <Image src={relifeLogo} fit="contain" w={200} />
        </Group>

        <Stack spacing="xs" align="center">
          <Title order={1} ta="center">
            Open Access Tool Template
          </Title>
          <Title order={3} c="dimmed" ta="center">
            Authentication with Supabase using Keycloak as provider
          </Title>
        </Stack>

        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Stack spacing="md">
            <Group>
              <ThemeIcon size="lg" radius="md" variant="light" color="blue">
                <IconBrandSupabase
                  style={{ width: rem(20), height: rem(20) }}
                />
              </ThemeIcon>
              <div>
                <Text size="sm" c="dimmed">
                  Configuration Details
                </Text>
                <Text size="lg" fw={500}>
                  Service Endpoints
                </Text>
              </div>
            </Group>

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
          </Stack>
        </Card>

        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Stack spacing="md">
            <Group>
              <ThemeIcon size="lg" radius="md" variant="light" color="teal">
                <IconKey style={{ width: rem(20), height: rem(20) }} />
              </ThemeIcon>
              <div>
                <Text size="sm" c="dimmed">
                  About
                </Text>
                <Text size="lg" fw={500}>
                  Authentication Flow
                </Text>
              </div>
            </Group>

            <Text>
              This is a minimal example that shows how to configure a Vite +
              React + Mantine web application for integration with ReLIFE&apos;s
              backend services, which are based on Supabase as the data layer
              and Keycloak for identity management.
            </Text>

            <Text>
              This example demonstrates Keycloak authentication through a
              Supabase client. Users in Keycloak can log in while leveraging
              Supabase libraries for simplified data handling.
            </Text>
          </Stack>
        </Card>

        {!session ? (
          <Button onClick={handleLogin} variant="filled" size="lg" fullWidth>
            Sign in with Supabase via Keycloak
          </Button>
        ) : (
          <Card shadow="sm" padding="lg" radius="md" withBorder>
            <Stack spacing="md">
              <Group>
                <ThemeIcon size="lg" radius="md" variant="light" color="green">
                  <IconUser style={{ width: rem(20), height: rem(20) }} />
                </ThemeIcon>
                <div>
                  <Text size="sm" c="dimmed">
                    User Profile
                  </Text>
                  <Text size="lg" fw={500}>
                    Account Information
                  </Text>
                </div>
              </Group>

              <Stack spacing="xs">
                <>
                  <Group position="apart">
                    <Text c="dimmed">Email</Text>
                    <Code>{session.user.email}</Code>
                  </Group>
                  <Text size="xs" c="dimmed" fs="italic" mt={-10}>
                    Email read directly from the Supabase access token issued to
                    the browser
                  </Text>
                </>

                {fullName && (
                  <>
                    <Group position="apart">
                      <Text c="dimmed">Full Name</Text>
                      <Text fw={500}>{fullName}</Text>
                    </Group>
                    <Text size="xs" c="dimmed" fs="italic" mt={-10}>
                      Full name retrieved from the backend service API by
                      passing the Supabase access token
                    </Text>
                  </>
                )}
              </Stack>

              <Button
                fullWidth
                onClick={handleLogout}
                variant="light"
                color="red"
                size="md"
                mt="md"
              >
                Sign Out
              </Button>
            </Stack>
          </Card>
        )}

        {session && <ReportRequests session={session} />}
      </Stack>
    </Container>
  );
}

export default App;
