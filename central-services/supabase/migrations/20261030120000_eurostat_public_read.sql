-- ============================================================================
-- Eurostat Public Read Access
-- ============================================================================

-- Lets the web UI read Eurostat prices and their review status, for logged-in
-- and anonymous users alike. eurostat_runs stays service-role only, and only
-- the service role can write.

-- ============================================================================
-- Row Level Security Policies
-- ============================================================================

-- eurostat_latest is a security_invoker view, so readers also need this policy
-- on the underlying table.
DROP POLICY IF EXISTS "anonymous users read eurostat observations"
  ON public.eurostat_observations;

CREATE POLICY "anonymous users read eurostat observations"
  ON public.eurostat_observations
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- The web UI skips values whose flag is open or rejected.
DROP POLICY IF EXISTS "anonymous users read eurostat quality flags"
  ON public.eurostat_quality_flags;

CREATE POLICY "anonymous users read eurostat quality flags"
  ON public.eurostat_quality_flags
  FOR SELECT
  TO anon, authenticated
  USING (true);

-- ============================================================================
-- Grants
-- ============================================================================

GRANT SELECT ON public.eurostat_observations TO anon, authenticated;
GRANT SELECT ON public.eurostat_latest TO anon, authenticated;
GRANT SELECT ON public.eurostat_quality_flags TO anon, authenticated;
