# Eurostat Ingestion Job

A small CLI that pulls Eurostat datasets into the central Supabase so ReLIFE services can read them instead of hard-coding values. Every revision is kept: a revised value or flag is appended, never overwritten.

## Datasets

| Code         | Content                                                                                                                            |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| `nrg_pc_204` | Household electricity prices, half-yearly. Band `KWH2500-4999`, all taxes, `EUR` per `KWH`. EU27 and `EU27_2020`, from 2015.       |
| `nrg_pc_202` | Household gas prices, half-yearly. Band `GJ20-199`, all taxes, `EUR` per `KWH`. EU27 except CY and MT, and `EU27_2020`, from 2015. |
| `nrg_chdd_a` | Heating degree days (`HDD` only), yearly. EU27 and `EU27_2020`, from 2015.                                                         |

> [!NOTE]
> The list lives in `DATASETS` in `src/relife_eurostat/datasets.py`.

## Usage

The job talks to Supabase only through its API, with the service role key:

```console
export SUPABASE_URL=http://localhost:8000
export SUPABASE_SERVICE_ROLE_KEY=...

# Dry run: fetch and print counts of new and changed values, write nothing
uv run relife-eurostat sync

# Store new and changed values
uv run relife-eurostat sync --apply
```

From the repository root, the same commands read the keys from `.env.keys`:

```console
task central:eurostat:sync
task central:eurostat:sync -- --apply
```

The CLI exits non-zero on failure.

## Storage

Schema: `central-services/supabase/migrations/*_eurostat.sql`. RLS is on with no policies (service role only).

- `eurostat_runs`: one row per `--apply` run (`running` → `succeeded` / `failed`)
- `eurostat_observations`: append-only revisions, linked to the run that wrote them
- `eurostat_latest`: newest revision per series and period

A row is stored when the value or flag is new or changed (e.g. provisional `p` → final). Missing values are stored as `NULL`.
