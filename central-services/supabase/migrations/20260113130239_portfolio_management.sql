-- ============================================================================
-- Portfolio Management Tables for ReLIFE Web UI
-- ============================================================================

-- ============================================================================
-- Configuration Table
-- ============================================================================
-- Stores application configuration values that can be changed without migrations
CREATE TABLE IF NOT EXISTS public.app_config (
  key VARCHAR(100) PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Helper function to get config values with type casting
CREATE OR REPLACE FUNCTION public.get_config_bigint(p_key TEXT, p_default BIGINT DEFAULT 0)
RETURNS BIGINT AS $$
DECLARE
  v_value TEXT;
BEGIN
  SELECT value INTO v_value FROM public.app_config WHERE key = p_key;
  IF v_value IS NULL THEN
    RETURN p_default;
  END IF;
  RETURN v_value::BIGINT;
EXCEPTION
  WHEN OTHERS THEN
    RETURN p_default;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================================
-- Portfolio Tables
-- ============================================================================

-- Table: portfolios
CREATE TABLE IF NOT EXISTS public.portfolios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT unique_portfolio_name_per_user UNIQUE (user_id, name)
);

CREATE INDEX IF NOT EXISTS idx_portfolios_user_id ON public.portfolios(user_id);

-- Table: portfolio_files
-- Note: MIME type validation is handled at the application/frontend level
CREATE TABLE IF NOT EXISTS public.portfolio_files (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  portfolio_id UUID NOT NULL REFERENCES public.portfolios(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  original_filename VARCHAR(500) NOT NULL,
  storage_path VARCHAR(1000) NOT NULL UNIQUE,
  mime_type VARCHAR(100) NOT NULL,
  file_size BIGINT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT valid_file_size CHECK (file_size > 0)
);

CREATE INDEX IF NOT EXISTS idx_portfolio_files_portfolio_id ON public.portfolio_files(portfolio_id);
CREATE INDEX IF NOT EXISTS idx_portfolio_files_user_id ON public.portfolio_files(user_id);

-- Table: user_storage_quotas
CREATE TABLE IF NOT EXISTS public.user_storage_quotas (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  used_bytes BIGINT NOT NULL DEFAULT 0,
  max_bytes BIGINT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT non_negative_usage CHECK (used_bytes >= 0)
);

-- ============================================================================
-- Row Level Security Policies
-- ============================================================================

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.portfolios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.portfolio_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_storage_quotas ENABLE ROW LEVEL SECURITY;

-- App config policies (read-only for authenticated users)
CREATE POLICY "Anyone can read app config" ON public.app_config
  FOR SELECT USING (true);

-- Portfolios policies
CREATE POLICY "Users can view own portfolios" ON public.portfolios
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own portfolios" ON public.portfolios
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own portfolios" ON public.portfolios
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own portfolios" ON public.portfolios
  FOR DELETE USING (auth.uid() = user_id);

-- Portfolio files policies
CREATE POLICY "Users can view own files" ON public.portfolio_files
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can create own files" ON public.portfolio_files
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own files" ON public.portfolio_files
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own files" ON public.portfolio_files
  FOR DELETE USING (auth.uid() = user_id);

-- Quota policies
CREATE POLICY "Users can view own quota" ON public.user_storage_quotas
  FOR SELECT USING (auth.uid() = user_id);

-- ============================================================================
-- Quota Management Functions and Triggers
-- ============================================================================

-- Get the effective max bytes for a user (user-specific or global default)
CREATE OR REPLACE FUNCTION public.get_user_max_bytes(p_user_id UUID)
RETURNS BIGINT AS $$
DECLARE
  v_user_max BIGINT;
BEGIN
  SELECT max_bytes INTO v_user_max
  FROM public.user_storage_quotas
  WHERE user_id = p_user_id;

  IF v_user_max IS NOT NULL THEN
    RETURN v_user_max;
  END IF;

  RETURN public.get_config_bigint('storage.default_quota_bytes', 524288000);
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- Ensure user has a quota record
CREATE OR REPLACE FUNCTION public.ensure_user_quota()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.user_storage_quotas (user_id)
  VALUES (NEW.user_id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER ensure_quota_on_file_insert
  BEFORE INSERT ON public.portfolio_files
  FOR EACH ROW EXECUTE FUNCTION public.ensure_user_quota();

-- Update quota on file upload
CREATE OR REPLACE FUNCTION public.update_quota_on_upload()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.user_storage_quotas
  SET used_bytes = used_bytes + NEW.file_size, updated_at = NOW()
  WHERE user_id = NEW.user_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER quota_update_on_insert
  AFTER INSERT ON public.portfolio_files
  FOR EACH ROW EXECUTE FUNCTION public.update_quota_on_upload();

-- Update quota on file delete
CREATE OR REPLACE FUNCTION public.update_quota_on_delete()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.user_storage_quotas
  SET used_bytes = GREATEST(0, used_bytes - OLD.file_size), updated_at = NOW()
  WHERE user_id = OLD.user_id;
  RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER quota_update_on_delete
  AFTER DELETE ON public.portfolio_files
  FOR EACH ROW EXECUTE FUNCTION public.update_quota_on_delete();

-- Check if user can upload a file of given size
CREATE OR REPLACE FUNCTION public.check_upload_quota(p_user_id UUID, p_file_size BIGINT)
RETURNS BOOLEAN AS $$
DECLARE
  v_current_usage BIGINT;
  v_max_allowed BIGINT;
  v_max_file_size BIGINT;
BEGIN
  v_max_file_size := public.get_config_bigint('storage.max_file_size_bytes', 52428800);
  IF p_file_size > v_max_file_size THEN
    RETURN FALSE;
  END IF;

  SELECT used_bytes INTO v_current_usage
  FROM public.user_storage_quotas
  WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    v_current_usage := 0;
  END IF;

  v_max_allowed := public.get_user_max_bytes(p_user_id);
  RETURN (v_current_usage + p_file_size) <= v_max_allowed;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Grants
-- ============================================================================

GRANT SELECT ON public.app_config TO anon, authenticated;
GRANT ALL ON public.app_config TO postgres, service_role;

GRANT ALL ON public.portfolios TO anon, authenticated, postgres, service_role;
GRANT ALL ON public.portfolio_files TO anon, authenticated, postgres, service_role;
GRANT ALL ON public.user_storage_quotas TO anon, authenticated, postgres, service_role;

-- ============================================================================
-- Default Configuration Values
-- ============================================================================
INSERT INTO
  public.app_config (key, value, description)
VALUES
  (
    'storage.max_file_size_bytes',
    '52428800',
    'Maximum file size in bytes (default: 50MB)'
  ),
  (
    'storage.default_quota_bytes',
    '524288000',
    'Default storage quota per user in bytes (default: 500MB)'
  ) ON CONFLICT (key) DO
UPDATE
SET
  value = EXCLUDED.value,
  description = EXCLUDED.description,
  updated_at = NOW()
WHERE
  (
    public.app_config.value,
    public.app_config.description
  ) IS DISTINCT
FROM
  (EXCLUDED.value, EXCLUDED.description);

-- ============================================================================
-- Storage Bucket
-- ============================================================================
INSERT INTO
  storage.buckets (
    id,
    name,
    public,
    avif_autodetection,
    file_size_limit,
    allowed_mime_types
  )
VALUES
  (
    'portfolio-files',
    'portfolio-files',
    false,
    false,
    NULL,
    NULL
  ) ON CONFLICT (id) DO
UPDATE
SET
  name = EXCLUDED.name,
  public = EXCLUDED.public,
  avif_autodetection = EXCLUDED.avif_autodetection,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types
WHERE
  (
    storage.buckets.name,
    storage.buckets.public,
    storage.buckets.avif_autodetection,
    storage.buckets.file_size_limit,
    storage.buckets.allowed_mime_types
  ) IS DISTINCT
FROM
  (
    EXCLUDED.name,
    EXCLUDED.public,
    EXCLUDED.avif_autodetection,
    EXCLUDED.file_size_limit,
    EXCLUDED.allowed_mime_types
  );