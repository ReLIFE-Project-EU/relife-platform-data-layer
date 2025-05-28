import {
  ActionIcon,
  Badge,
  Button,
  Card,
  FileButton,
  Group,
  Progress,
  rem,
  Stack,
  Table,
  Text,
  ThemeIcon,
} from "@mantine/core";
import { IconFile, IconUpload } from "@tabler/icons-react";
import PropTypes from "prop-types";
import { useCallback, useEffect, useState } from "react";
import { getServiceApiUrl } from "../auth";

export default function FileStorage({ session }) {
  const [files, setFiles] = useState([]);
  const [uploading, setUploading] = useState(false);
  const [progress, setProgress] = useState(0);

  const fetchFiles = useCallback(async () => {
    try {
      const apiUrl = getServiceApiUrl();

      const response = await fetch(`${apiUrl}/storage`, {
        headers: {
          Authorization: `Bearer ${session.access_token}`,
        },
      });

      if (!response.ok) {
        throw new Error("Failed to fetch files");
      }

      const data = await response.json();
      setFiles(data);
    } catch (error) {
      console.error("Error fetching files:", error);
    }
  }, [session.access_token]);

  useEffect(() => {
    fetchFiles();
  }, [fetchFiles]);

  const handleFileUpload = async (file) => {
    if (!file) return;

    setUploading(true);
    setProgress(0);

    const formData = new FormData();
    formData.append("file", file);

    try {
      const response = await fetch("/api/storage", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${session.access_token}`,
        },
        body: formData,
      });

      if (!response.ok) throw new Error("Upload failed");

      const result = await response.json();
      setFiles((prev) => [
        ...prev,
        {
          name: file.name,
          size: file.size,
          created_at: new Date().toISOString(),
          public_url: result.public_url,
        },
      ]);
    } catch (error) {
      console.error("Error uploading file:", error);
    } finally {
      setUploading(false);
      setProgress(0);
    }
  };

  const formatFileSize = (bytes) => {
    if (bytes === 0) return "0 Bytes";
    const k = 1024;
    const sizes = ["Bytes", "KB", "MB", "GB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + " " + sizes[i];
  };

  return (
    <Card shadow="sm" padding="lg" radius="md" withBorder>
      <Stack spacing="md">
        <Group>
          <ThemeIcon size="lg" radius="md" variant="light" color="blue">
            <IconFile style={{ width: rem(20), height: rem(20) }} />
          </ThemeIcon>
          <div>
            <Text size="sm" c="dimmed">
              File Management
            </Text>
            <Text size="lg" fw={500}>
              Storage Example
            </Text>
          </div>
        </Group>

        <Text>
          This section demonstrates how to upload and view dataset files using
          Supabase&apos;s Storage API, which is backed by MinIO (S3-compatible
          storage).
        </Text>

        <Group position="apart">
          <Text size="sm" c="dimmed">
            Upload and manage your files
          </Text>
          <FileButton
            onChange={handleFileUpload}
            accept="*/*"
            disabled={uploading}
          >
            {(props) => (
              <Button
                {...props}
                leftIcon={<IconUpload size={rem(16)} />}
                loading={uploading}
              >
                Upload File
              </Button>
            )}
          </FileButton>
        </Group>

        {uploading && <Progress value={progress} size="sm" radius="xl" />}

        {files.length > 0 ? (
          <Table>
            <Table.Thead>
              <Table.Tr>
                <Table.Th>File Name</Table.Th>
                <Table.Th>Size</Table.Th>
                <Table.Th>Upload Date</Table.Th>
                <Table.Th>Actions</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {files.map((file) => (
                <Table.Tr key={file.name}>
                  <Table.Td>
                    <Group gap="xs">
                      <IconFile size={rem(16)} />
                      <Text size="sm">{file.name}</Text>
                    </Group>
                  </Table.Td>
                  <Table.Td>
                    <Badge variant="light" color="blue">
                      {formatFileSize(file.size)}
                    </Badge>
                  </Table.Td>
                  <Table.Td>
                    <Text size="sm">
                      {new Date(file.created_at).toLocaleDateString()}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Group gap="xs">
                      <ActionIcon
                        variant="light"
                        color="blue"
                        component="a"
                        href={file.public_url}
                        target="_blank"
                      >
                        <IconFile size={rem(16)} />
                      </ActionIcon>
                    </Group>
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        ) : (
          <Text c="dimmed" ta="center" py="xl">
            No files uploaded yet. Click the upload button to get started.
          </Text>
        )}
      </Stack>
    </Card>
  );
}

FileStorage.propTypes = {
  session: PropTypes.shape({
    access_token: PropTypes.string.isRequired,
  }).isRequired,
};
