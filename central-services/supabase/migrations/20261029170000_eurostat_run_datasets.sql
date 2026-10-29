-- ============================================================================
-- Eurostat Run Datasets
-- ============================================================================

-- Eurostat "Last data change" seen per dataset code, e.g.
-- {"nrg_pc_204": "2026-10-19T23:00:00+0200"}. The next run skips a dataset
-- whose value matches the newest succeeded run that recorded it.
ALTER TABLE public.eurostat_runs
  ADD COLUMN IF NOT EXISTS datasets JSONB;

-- Whether any dataset's "Last data change" differed from the recorded one.
ALTER TABLE public.eurostat_runs
  ADD COLUMN IF NOT EXISTS has_new_data BOOLEAN;
