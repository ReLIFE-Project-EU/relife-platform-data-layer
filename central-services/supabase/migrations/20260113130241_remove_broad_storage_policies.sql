-- ============================================================================
-- Remove overly broad storage.objects policies
-- ============================================================================
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON storage.objects;

DROP POLICY IF EXISTS "Enable delete for users based on user id" ON storage.objects;

DROP POLICY IF EXISTS "Enable insert for users based on user id" ON storage.objects;

DROP POLICY IF EXISTS "Enable update for users based on user id" ON storage.objects;

DROP POLICY IF EXISTS "Enable users to view their own data only" ON storage.objects;