-- ============================================================================
-- Renovation Strategy Explorer Forecasting Cache
-- ============================================================================

-- Stores publishable cache batches for RSE precomputed Forecasting results.
CREATE TABLE IF NOT EXISTS public.rse_cache_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cache_version TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK (status IN ('draft', 'published', 'retired')),
  description TEXT,
  generated_by TEXT NOT NULL DEFAULT 'manual-seed',
  forecasting_service_version TEXT,
  co2_method TEXT NOT NULL DEFAULT 'forecasting-carrier-split-final-energy-gas-thermal-mvp',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  published_at TIMESTAMPTZ
);

-- Stores one cached result per cache version, archetype, and package.
CREATE TABLE IF NOT EXISTS public.rse_forecasting_cache_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cache_version TEXT NOT NULL REFERENCES public.rse_cache_versions(cache_version),
  archetype_country TEXT NOT NULL,
  archetype_category TEXT NOT NULL,
  archetype_name TEXT NOT NULL,
  package_id TEXT NOT NULL,
  payload_schema_version INTEGER NOT NULL DEFAULT 1,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (
    cache_version,
    archetype_country,
    archetype_category,
    archetype_name,
    package_id
  )
);

CREATE INDEX IF NOT EXISTS rse_cache_entries_lookup_idx
  ON public.rse_forecasting_cache_entries (
    cache_version,
    archetype_country,
    archetype_category,
    archetype_name,
    package_id
  );

CREATE INDEX IF NOT EXISTS rse_cache_entries_package_idx
  ON public.rse_forecasting_cache_entries (cache_version, package_id);

-- ============================================================================
-- Row Level Security Policies
-- ============================================================================

ALTER TABLE public.rse_cache_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rse_forecasting_cache_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anonymous users read published rse cache versions"
  ON public.rse_cache_versions;

CREATE POLICY "anonymous users read published rse cache versions"
  ON public.rse_cache_versions
  FOR SELECT
  TO anon, authenticated
  USING (status = 'published');

DROP POLICY IF EXISTS "anonymous users read published rse cache entries"
  ON public.rse_forecasting_cache_entries;

CREATE POLICY "anonymous users read published rse cache entries"
  ON public.rse_forecasting_cache_entries
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.rse_cache_versions v
      WHERE v.cache_version = rse_forecasting_cache_entries.cache_version
        AND v.status = 'published'
    )
  );

-- ============================================================================
-- Grants
-- ============================================================================

GRANT SELECT ON public.rse_cache_versions TO anon, authenticated;
GRANT SELECT ON public.rse_forecasting_cache_entries TO anon, authenticated;

GRANT ALL ON public.rse_cache_versions TO postgres, service_role;
GRANT ALL ON public.rse_forecasting_cache_entries TO postgres, service_role;
