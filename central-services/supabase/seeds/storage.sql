SET
    session_replication_role = replica;

--
-- PostgreSQL database dump
--
-- Dumped from database version 15.1 (Ubuntu 15.1-1.pgdg20.04+1)
-- Dumped by pg_dump version 15.8
SET
    statement_timeout = 0;

SET
    lock_timeout = 0;

SET
    idle_in_transaction_session_timeout = 0;

SET
    client_encoding = 'UTF8';

SET
    standard_conforming_strings = on;

SELECT
    pg_catalog.set_config ('search_path', '', false);

SET
    check_function_bodies = false;

SET
    xmloption = content;

SET
    client_min_messages = warning;

SET
    row_security = off;

--
-- Data for Name: buckets; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--
INSERT INTO
    "storage"."buckets" (
        "id",
        "name",
        "owner",
        "created_at",
        "updated_at",
        "public",
        "avif_autodetection",
        "file_size_limit",
        "allowed_mime_types",
        "owner_id"
    )
VALUES
    (
        'example_bucket',
        'example_bucket',
        NULL,
        '2025-04-01 16:19:47.766607+00',
        '2025-04-01 16:19:47.766607+00',
        true,
        false,
        NULL,
        NULL,
        NULL
    );

--
-- Data for Name: objects; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--
--
-- Data for Name: s3_multipart_uploads; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--
--
-- Data for Name: s3_multipart_uploads_parts; Type: TABLE DATA; Schema: storage; Owner: supabase_storage_admin
--
--
-- PostgreSQL database dump complete
--
RESET ALL;