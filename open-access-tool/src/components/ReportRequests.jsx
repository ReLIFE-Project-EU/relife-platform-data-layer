import {
  Alert,
  Button,
  Card,
  Group,
  Loader,
  Stack,
  Table,
  Text,
  ThemeIcon,
  Title,
  rem,
} from "@mantine/core";
import {
  IconAlertCircle,
  IconCirclePlus,
  IconListDetails,
} from "@tabler/icons-react";
import PropTypes from "prop-types";
import { useCallback, useEffect, useState } from "react";
import { getServiceApiUrl } from "../auth";

async function fetchReportRequests(accessToken) {
  const apiUrl = getServiceApiUrl();

  const response = await fetch(`${apiUrl}/report-request`, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    const errorData = await response.text();

    throw new Error(
      `Failed to fetch report requests: ${response.status} ${errorData}`
    );
  }

  return response.json();
}

async function createReportRequest(accessToken) {
  const apiUrl = getServiceApiUrl();

  const response = await fetch(`${apiUrl}/report-request`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });

  if (!response.ok) {
    const errorData = await response.text();

    throw new Error(
      `Failed to create report request: ${response.status} ${errorData}`
    );
  }

  return response.json();
}

function ReportRequests({ session }) {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [creating, setCreating] = useState(false);

  const loadRequests = useCallback(async () => {
    if (!session?.access_token) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const data = await fetchReportRequests(session.access_token);
      setRequests(data || []);
    } catch (err) {
      console.error("Error fetching report requests:", err);
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [session?.access_token]);

  useEffect(() => {
    loadRequests();
  }, [session, loadRequests]); // Reload when session changes

  const handleCreateRequest = useCallback(async () => {
    if (!session?.access_token) {
      return;
    }

    setCreating(true);
    setError(null);

    try {
      await createReportRequest(session.access_token);
      await loadRequests();
    } catch (err) {
      console.error("Error creating report request:", err);
      setError(err.message);
    } finally {
      setCreating(false);
    }
  }, [session?.access_token, loadRequests]);

  const rows = requests.map((request) => (
    <Table.Tr key={request.id}>
      <Table.Td>{request.id}</Table.Td>
      <Table.Td>{new Date(request.created_at).toLocaleString()}</Table.Td>
      <Table.Td>{request.description || "N/A"}</Table.Td>
      <Table.Td>{request.result || "N/A"}</Table.Td>
    </Table.Tr>
  ));

  return (
    <Card shadow="sm" padding="lg" radius="md" withBorder>
      <Stack spacing="md">
        <Group>
          <ThemeIcon size="lg" radius="md" variant="light" color="grape">
            <IconListDetails style={{ width: rem(20), height: rem(20) }} />
          </ThemeIcon>
          <div>
            <Text size="sm" c="dimmed">
              Data Access Example
            </Text>
            <Title order={4}>Report Requests</Title>
          </div>
        </Group>

        <Text>
          This section demonstrates reading and writing data through the ReLIFE
          Service API, which uses Supabase as its data layer. By leveraging
          Supabase, we get Row-Level Security and access policies with minimal
          effort.
        </Text>

        {error && (
          <Alert
            icon={<IconAlertCircle size="1rem" />}
            title="Error"
            color="red"
            variant="light"
          >
            {error}
          </Alert>
        )}

        <Button
          onClick={handleCreateRequest}
          leftSection={<IconCirclePlus size={14} />}
          loading={creating}
          disabled={loading || creating}
          variant="outline"
        >
          Create New Report Request
        </Button>

        {loading ? (
          <Group justify="center" py="md">
            <Loader />
            <Text>Loading requests...</Text>
          </Group>
        ) : requests.length > 0 ? (
          <Table striped highlightOnHover withTableBorder withColumnBorders>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>ID</Table.Th>
                <Table.Th>Created At</Table.Th>
                <Table.Th>Description</Table.Th>
                <Table.Th>Result</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>{rows}</Table.Tbody>
          </Table>
        ) : (
          <Text c="dimmed" ta="center" py="md">
            No report requests found for this user.
          </Text>
        )}
      </Stack>
    </Card>
  );
}

export default ReportRequests;

ReportRequests.propTypes = {
  session: PropTypes.shape({
    access_token: PropTypes.string,
  }),
};
