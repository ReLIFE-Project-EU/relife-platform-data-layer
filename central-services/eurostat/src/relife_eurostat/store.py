from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Sequence, cast

from postgrest import ReturnMethod
from supabase import Client

from relife_eurostat.models import Observation, QualityFlag, RunSummary

RUNS_TABLE = "eurostat_runs"
OBSERVATIONS_TABLE = "eurostat_observations"
LATEST_VIEW = "eurostat_latest"
FLAGS_TABLE = "eurostat_quality_flags"

# Columns of the eurostat_observations_run_key_idx unique index
OBSERVATION_RUN_KEY = "run_id,dataset_code,dimensions,geo,period"

# Columns of the eurostat_quality_flags_key_idx unique index
FLAG_KEY = "dataset_code,dimensions,geo,period,check"

# Stays within PostgREST's default max-rows so every page is complete
PAGE_SIZE = 1000
INSERT_BATCH_SIZE = 500


class Store:
    """Reads and writes Eurostat runs, observations and quality flags through the Supabase API."""

    def __init__(self, client: Client) -> None:
        self._client = client

    def latest(self, dataset_code: str) -> list[Observation]:
        observations: list[Observation] = []
        start = 0

        while True:
            response = (
                self._client.table(LATEST_VIEW)
                # Cast NUMERIC to text: as a JSON number it would arrive as a
                # float and could lose precision
                .select("dataset_code,dimensions,geo,period,value::text,flag")
                .eq("dataset_code", dataset_code)
                .order("id")
                .range(start, start + PAGE_SIZE - 1)
                .execute()
            )

            rows = cast(list[dict[str, Any]], response.data)
            observations.extend(_row_to_observation(row) for row in rows)

            if len(rows) < PAGE_SIZE:
                return observations

            start += PAGE_SIZE

    def last_data_change(self, dataset_code: str) -> str | None:
        """Return the "Last data change" recorded by the newest succeeded run that saw the dataset."""

        # Runs left running or marked failed may not have stored their values
        response = (
            self._client.table(RUNS_TABLE)
            .select("datasets")
            .eq("status", "succeeded")
            .not_.is_(f"datasets->>{dataset_code}", "null")
            .order("started_at", desc=True)
            .limit(1)
            .execute()
        )

        rows = cast(list[dict[str, Any]], response.data)
        return str(rows[0]["datasets"][dataset_code]) if rows else None

    def start_run(self) -> str:
        response = (
            self._client.table(RUNS_TABLE).insert({"status": "running"}).execute()
        )
        rows = cast(list[dict[str, Any]], response.data)
        return str(rows[0]["id"])

    def insert_observations(
        self, run_id: str, observations: Sequence[Observation]
    ) -> None:
        rows = [_observation_to_row(run_id, item) for item in observations]

        # ON CONFLICT DO NOTHING: re-sending a batch that already reached the
        # database (e.g. after a timeout) is a no-op instead of a duplicate
        for offset in range(0, len(rows), INSERT_BATCH_SIZE):
            self._client.table(OBSERVATIONS_TABLE).upsert(
                rows[offset : offset + INSERT_BATCH_SIZE],
                on_conflict=OBSERVATION_RUN_KEY,
                ignore_duplicates=True,
                returning=ReturnMethod.minimal,
            ).execute()

    def insert_flags(self, run_id: str, flags: Sequence[QualityFlag]) -> int:
        """Add flags to the review list and return how many were not there yet."""

        rows = [_flag_to_row(run_id, flag) for flag in flags]
        inserted = 0

        # ON CONFLICT DO NOTHING keeps an already raised flag, and the status a
        # reviewer gave it; only the rows actually inserted are returned
        for offset in range(0, len(rows), INSERT_BATCH_SIZE):
            response = (
                self._client.table(FLAGS_TABLE)
                .upsert(
                    rows[offset : offset + INSERT_BATCH_SIZE],
                    on_conflict=FLAG_KEY,
                    ignore_duplicates=True,
                    returning=ReturnMethod.representation,
                )
                .execute()
            )
            inserted += len(cast(list[dict[str, Any]], response.data))

        return inserted

    def succeed_run(self, run_id: str, summary: RunSummary) -> None:
        self._finish_run(
            run_id,
            {
                "status": "succeeded",
                "added_count": summary.added_count,
                "changed_count": summary.changed_count,
                "flag_count": summary.flag_count,
                "datasets": dict(summary.datasets),
                "has_new_data": summary.has_new_data,
            },
        )

    def fail_run(self, run_id: str, error: str) -> None:
        self._finish_run(run_id, {"status": "failed", "error": error})

    def _finish_run(self, run_id: str, fields: dict[str, Any]) -> None:
        finished_at = datetime.now(timezone.utc).isoformat()

        self._client.table(RUNS_TABLE).update(
            {**fields, "finished_at": finished_at},
            returning=ReturnMethod.minimal,
        ).eq("id", run_id).execute()


def _row_to_observation(row: dict[str, Any]) -> Observation:
    value = row["value"]

    return Observation(
        dataset_code=row["dataset_code"],
        dimensions=row["dimensions"],
        geo=row["geo"],
        period=row["period"],
        value=None if value is None else Decimal(value),
        flag=row["flag"],
    )


def _observation_to_row(run_id: str, observation: Observation) -> dict[str, Any]:
    # NUMERIC is sent as a string so no precision is lost on the way in
    value = observation.value

    return {
        "run_id": run_id,
        "dataset_code": observation.dataset_code,
        "dimensions": dict(observation.dimensions),
        "geo": observation.geo,
        "period": observation.period,
        "value": None if value is None else str(value),
        "flag": observation.flag,
    }


def _flag_to_row(run_id: str, flag: QualityFlag) -> dict[str, Any]:
    return {
        "run_id": run_id,
        "dataset_code": flag.dataset_code,
        "dimensions": dict(flag.dimensions),
        "geo": flag.geo,
        "period": flag.period,
        "check": flag.check,
        "reason": flag.reason,
    }
