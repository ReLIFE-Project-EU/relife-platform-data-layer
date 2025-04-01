import {
  Alert,
  Card,
  Group,
  Stack,
  Table,
  Text,
  ThemeIcon,
  rem,
} from "@mantine/core";
import { IconAlertCircle, IconLock } from "@tabler/icons-react";
import PropTypes from "prop-types";
import { useEffect, useState } from "react";
import { getServiceApiUrl, supabase } from "../auth";

export default function UserList({ session }) {
  const [users, setUsers] = useState([]);
  const [error, setError] = useState(null);

  useEffect(() => {
    const fetchUsers = async () => {
      try {
        const {
          data: { session: currentSession },
        } = await supabase.auth.getSession();

        if (!currentSession) return;

        const apiUrl = getServiceApiUrl();

        const response = await fetch(`${apiUrl}/admin/users`, {
          headers: {
            Authorization: `Bearer ${currentSession.access_token}`,
          },
        });

        if (!response.ok) {
          throw new Error("Failed to fetch users");
        }

        const data = await response.json();
        setUsers(data);
      } catch (err) {
        setError(err.message);
      }
    };

    fetchUsers();
  }, [session]);

  return (
    <Card shadow="sm" padding="lg" radius="md" withBorder>
      <Stack spacing="md">
        <Group>
          <ThemeIcon size="lg" radius="md" variant="light" color="violet">
            <IconLock style={{ width: rem(20), height: rem(20) }} />
          </ThemeIcon>
          <div>
            <Text size="sm" c="dimmed">
              User Management
            </Text>
            <Text size="lg" fw={500}>
              Admin Access Example
            </Text>
          </div>
        </Group>

        <Text>
          This section demonstrates accessing an API endpoint that uses a
          privileged Supabase client and requires the user to have an admin role
          in Keycloak.
        </Text>

        {error ? (
          <Alert
            icon={<IconAlertCircle size="1rem" />}
            title="Error"
            color="red"
            variant="light"
          >
            {error}
          </Alert>
        ) : (
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Name</Table.Th>
                <Table.Th>Created At</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {users.map((user) => (
                <Table.Tr key={user.id}>
                  <Table.Td>{user.name}</Table.Td>
                  <Table.Td>
                    {new Date(user.created_at).toLocaleString()}
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        )}
      </Stack>
    </Card>
  );
}

UserList.propTypes = {
  session: PropTypes.object.isRequired,
};
