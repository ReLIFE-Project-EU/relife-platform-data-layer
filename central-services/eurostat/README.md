# Eurostat Sync

Copies Eurostat energy data into the central Supabase once a week. Values are never overwritten: a revised value is stored as a new row.

## Datasets

- `nrg_pc_204`: household electricity prices, every six months
- `nrg_pc_202`: household gas prices, every six months
- `nrg_chdd_a`: heating degree days, yearly

To change the list, edit `DATASETS` in `src/relife_eurostat/datasets.py`.

## Run It

From the repository root, with Supabase running:

```console
task central:eurostat:deploy            # start the job and its weekly schedule
task central:eurostat:sync              # dry run: show what would change
task central:eurostat:sync -- --apply   # write the changes
task central:eurostat:clean             # stop and remove the containers
```

The job runs `sync --apply` on its own every Monday at 06:00 UTC. Check its output with `docker logs relife-eurostat-cron`.

A dataset that Eurostat hasn't changed since the last run is skipped. To force one, add `--dataset nrg_pc_204`.

The tasks read `SUPABASE_SERVICE_ROLE_KEY` from `.env.keys`.

To run it without Docker:

```console
export SUPABASE_URL=http://localhost:8000
export SUPABASE_SERVICE_ROLE_KEY=...
uv run relife-eurostat sync
```

## Tables

- `eurostat_runs`: one row per `--apply` run, with its status
- `eurostat_latest`: the newest value for each series and period
- `eurostat_observations`: every value ever stored
- `eurostat_quality_flags`: suspicious values to review

Only the service role can read or write them.

## Review Flags

Each run compares the newest period with the previous one. It flags a country whose value went missing, or whose change is very different from the other countries.

1. Open Studio at `SUPABASE_URL` and log in with `SUPABASE_DASHBOARD_USERNAME` and `SUPABASE_DASHBOARD_PASSWORD`.
2. Open the `eurostat_quality_flags` table and filter on `status = open`.
3. Read the `reason` and check the value on Eurostat.
4. Set `status` to `accepted` if the value is right, or `rejected` if it's wrong. A reviewed flag won't come back.
