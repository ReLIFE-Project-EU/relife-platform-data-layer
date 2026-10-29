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

# Dry run: fetch and print counts of new and changed values and the quality
# flags it would raise, write nothing
uv run relife-eurostat sync

# Store new and changed values and add flags to the review list
uv run relife-eurostat sync --apply

# Process one dataset even if Eurostat has not changed it
uv run relife-eurostat sync --apply --dataset nrg_pc_204
```

From the repository root, the same commands read the keys from `.env.keys`:

```console
task central:eurostat:sync
task central:eurostat:sync -- --apply
```

The CLI exits non-zero on failure, including for an unknown `--dataset` code.

## Skipping Unchanged Datasets

Each run first reads Eurostat's [data inventory](https://ec.europa.eu/eurostat/api/dissemination/files/inventory?type=data) and takes every dataset's "Last data change". A dataset is skipped, without downloading it, when that value matches the one recorded by the newest `succeeded` run that saw it. Runs left `running` or marked `failed` are ignored, so the next run processes their datasets again. In a quiet week a run writes nothing but its run row.

A configured dataset missing from the inventory fails the run, which catches renamed or retired datasets. `--dataset CODE` processes that dataset even if it has not changed, and checks only that dataset against the inventory. Use it after changing a dataset's query in `DATASETS`, since the inventory only reflects changes on Eurostat's side.

## Storage

Schema: `central-services/supabase/migrations/*_eurostat.sql`. RLS is on with no policies (service role only).

- `eurostat_runs`: one row per `--apply` run (`running` → `succeeded` / `failed`), with the number of flags raised in `flag_count` (including ones already in the review list), the "Last data change" seen per dataset in `datasets`, and whether any of them was new in `has_new_data`
- `eurostat_observations`: append-only revisions, linked to the run that wrote them
- `eurostat_latest`: newest revision per series and period
- `eurostat_quality_flags`: review list of suspicious values (see below)

A row is stored when the value or flag is new or changed (e.g. provisional `p` → final). Missing values are stored as `NULL`.

## Quality Flags

Each run compares the newest period to the previous one (per non-`geo` slice). Earlier periods are skipped, so the first load raises nothing.

- **`completeness`**: a country had a value last period and has none in the newest one
- **`outlier`**: a country's % change from last period stands out sharply from the other countries in the same slice. `EU27_2020` is left out; countries with a previous value of 0 are skipped.
