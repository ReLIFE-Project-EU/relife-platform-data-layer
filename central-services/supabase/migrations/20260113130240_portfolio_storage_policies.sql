-- ============================================================================
-- Storage Policies for portfolio-files bucket
-- ============================================================================
CREATE POLICY "Users can upload to their folder" ON storage.objects FOR
INSERT
  WITH CHECK (
    bucket_id = 'portfolio-files'
    AND (storage.foldername(name)) [1] = auth.uid() :: text
  );

CREATE POLICY "Users can view their portfolio files" ON storage.objects FOR
SELECT
  USING (
    bucket_id = 'portfolio-files'
    AND (storage.foldername(name)) [1] = auth.uid() :: text
  );

CREATE POLICY "Users can update their portfolio files" ON storage.objects FOR
UPDATE
  USING (
    bucket_id = 'portfolio-files'
    AND (storage.foldername(name)) [1] = auth.uid() :: text
  ) WITH CHECK (
    bucket_id = 'portfolio-files'
    AND (storage.foldername(name)) [1] = auth.uid() :: text
  );

CREATE POLICY "Users can delete their portfolio files" ON storage.objects FOR DELETE USING (
  bucket_id = 'portfolio-files'
  AND (storage.foldername(name)) [1] = auth.uid() :: text
);