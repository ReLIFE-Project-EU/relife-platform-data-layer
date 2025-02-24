import {
  Button,
  Code,
  Container,
  MantineProvider,
  Paper,
  Stack,
  Text,
  Title,
} from "@mantine/core";
import "@mantine/core/styles.css";
import { createClient } from "@supabase/supabase-js";
import { useEffect, useState } from "react";

function getClient() {
  const supabaseUrl =
    import.meta.env.VITE_SUPABASE_URL || "http://localhost:8000";

  const supabaseKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

  return createClient(supabaseUrl, supabaseKey);
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
  };

  return (
    <MantineProvider>
      <Container size="sm" py="xl">
        <Stack align="center" spacing="xl" justify="center">
          {!session ? (
            <Button onClick={handleLogin} variant="filled" size="lg">
              Sign In with Keycloak
            </Button>
          ) : (
            <Paper shadow="sm" p="md" withBorder>
              <Text>
                Signed in as: <Code>{session.user.email}</Code>
              </Text>
              <Button
                onClick={handleLogout}
                variant="light"
                color="red"
                size="sm"
                mt="sm"
              >
                Sign Out
              </Button>
            </Paper>
          )}

          <Title order={1} align="center">
            Welcome to the Open Access Tool
          </Title>

          <Text align="center">
            This is a minimal example that shows how to configure a Vite + React
            + Mantine web application for integration with ReLIFE&apos;s backend
            services, which are based on Supabase as the data layer and Keycloak
            for identity management.
          </Text>
        </Stack>
      </Container>
    </MantineProvider>
  );
}

export default App;
