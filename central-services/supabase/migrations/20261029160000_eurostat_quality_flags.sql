-- ============================================================================
-- Eurostat Quality Flags
-- ============================================================================

-- Number of quality flags a run raised, including ones already in the
-- review list from an earlier run.
ALTER TABLE public.eurostat_runs
  ADD COLUMN IF NOT EXISTS flag_count INTEGER;

-- Review list of suspicious Eurostat values, worked through in Supabase Studio
-- by setting status to accepted or rejected.
-- A flag points to a series and period, not to an observation row, because a
-- completeness flag is about a value that does not exist.
CREATE TABLE IF NOT EXISTS public.eurostat_quality_flags (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- Run that first raised the flag
  run_id UUID NOT NULL REFERENCES public.eurostat_runs(id),
  dataset_code TEXT NOT NULL,
  -- SDMX dimension codes except geo and time, as in eurostat_observations
  dimensions JSONB NOT NULL,
  geo TEXT NOT NULL,
  period TEXT NOT NULL,
  "check" TEXT NOT NULL
    CHECK ("check" IN ('completeness', 'outlier')),
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'accepted', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- A re-run skips flags it already raised (ON CONFLICT DO NOTHING), so a
-- reviewed flag keeps its status instead of reappearing as open.
CREATE UNIQUE INDEX IF NOT EXISTS eurostat_quality_flags_key_idx
  ON public.eurostat_quality_flags (dataset_code, dimensions, geo, period, "check");

CREATE INDEX IF NOT EXISTS eurostat_quality_flags_status_idx
  ON public.eurostat_quality_flags (status);

CREATE OR REPLACE FUNCTION public.eurostat_quality_flags_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SET search_path = '';

CREATE OR REPLACE TRIGGER eurostat_quality_flags_set_updated_at
  BEFORE UPDATE ON public.eurostat_quality_flags
  FOR EACH ROW EXECUTE FUNCTION public.eurostat_quality_flags_set_updated_at();

-- ============================================================================
-- Row Level Security Policies
-- ============================================================================

-- RLS is enabled with no policies: only the service role, which bypasses RLS,
-- can read or write this table.
ALTER TABLE public.eurostat_quality_flags ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- Grants
-- ============================================================================

-- Supabase grants new objects in public to anon and authenticated by default.
REVOKE ALL ON public.eurostat_quality_flags FROM anon, authenticated;

GRANT ALL ON public.eurostat_quality_flags TO postgres, service_role;
