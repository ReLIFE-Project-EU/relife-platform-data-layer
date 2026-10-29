-- ============================================================================
-- Eurostat Ingestion
-- ============================================================================

-- Stores one row per ingestion run of the Eurostat sync job.
CREATE TABLE IF NOT EXISTS public.eurostat_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'running'
    CHECK (status IN ('running', 'succeeded', 'failed')),
  error TEXT,
  added_count INTEGER,
  changed_count INTEGER
);

-- Stores every revision of every Eurostat observation. Rows are never updated
-- or deleted: a revised value or flag is appended as a new row.
CREATE TABLE IF NOT EXISTS public.eurostat_observations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id UUID NOT NULL REFERENCES public.eurostat_runs(id),
  dataset_code TEXT NOT NULL,
  -- SDMX dimension codes except geo and time, e.g. {"freq": "S", "tax": "I_TAX"}
  dimensions JSONB NOT NULL,
  -- Eurostat geo code: a country such as ES or an aggregate such as EU27_2020
  geo TEXT NOT NULL,
  -- Eurostat time period, e.g. 2024-S2
  period TEXT NOT NULL,
  -- NULL when Eurostat publishes the observation without a value
  value NUMERIC,
  -- Eurostat observation flag, e.g. p (provisional); NULL when final
  flag TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS eurostat_observations_latest_idx
  ON public.eurostat_observations (dataset_code, dimensions, geo, period, id DESC);

-- A run stores each series and period at most once, so a retried insert can
-- skip rows it already wrote (ON CONFLICT DO NOTHING) instead of duplicating
-- them. Also serves lookups by run.
CREATE UNIQUE INDEX IF NOT EXISTS eurostat_observations_run_key_idx
  ON public.eurostat_observations (run_id, dataset_code, dimensions, geo, period);

CREATE OR REPLACE FUNCTION public.eurostat_observations_append_only()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'eurostat_observations is append-only';
END;
$$ LANGUAGE plpgsql SET search_path = '';

-- CREATE OR REPLACE keeps the table guarded throughout, unlike DROP + CREATE
CREATE OR REPLACE TRIGGER eurostat_observations_append_only
  BEFORE UPDATE OR DELETE ON public.eurostat_observations
  FOR EACH ROW EXECUTE FUNCTION public.eurostat_observations_append_only();

-- Exposes the newest stored revision per series and period.
-- security_invoker makes the view apply the caller's RLS and grants instead of
-- the owner's, so it is no more readable than the underlying table.
CREATE OR REPLACE VIEW public.eurostat_latest
WITH (security_invoker = true)
AS
SELECT DISTINCT ON (dataset_code, dimensions, geo, period)
  id,
  run_id,
  dataset_code,
  dimensions,
  geo,
  period,
  value,
  flag,
  created_at
FROM public.eurostat_observations
ORDER BY dataset_code, dimensions, geo, period, id DESC;

-- ============================================================================
-- Row Level Security Policies
-- ============================================================================

-- RLS is enabled with no policies: only the service role, which bypasses RLS,
-- can read or write these tables.
ALTER TABLE public.eurostat_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eurostat_observations ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Grants
-- ============================================================================

-- Supabase grants new objects in public to anon and authenticated by default.
REVOKE ALL ON public.eurostat_runs FROM anon, authenticated;
REVOKE ALL ON public.eurostat_observations FROM anon, authenticated;
REVOKE ALL ON public.eurostat_latest FROM anon, authenticated;

GRANT ALL ON public.eurostat_runs TO postgres, service_role;
GRANT ALL ON public.eurostat_observations TO postgres, service_role;
GRANT SELECT ON public.eurostat_latest TO postgres, service_role;
