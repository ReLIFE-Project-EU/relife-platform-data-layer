from datetime import datetime, timezone
from decimal import Decimal
from typing import Any, Sequence, cast

from postgrest import ReturnMethod
from supabase import Client

from relife_eurostat.models import Observation

RUNS_TABLE = "eurostat_runs"
OBSERVATIONS_TABLE = "eurostat_observations"
LATEST_VIEW = "eurostat_latest"

# Columns of the eurostat_observations_run_key_idx unique index
OBSERVATION_RUN_KEY = "run_id,dataset_code,dimensions,geo,period"

# Stays within PostgREST's default max-rows so every page is complete
PAGE_SIZE = 1000
INSERT_BATCH_SIZE = 500


class Store:
    """Reads and writes Eurostat runs and observations through the Supabase API."""

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

    def succeed_run(self, run_id: str, added_count: int, changed_count: int) -> None:
        self._finish_run(
            run_id,
            {
                "status": "succeeded",
                "added_count": added_count,
                "changed_count": changed_count,
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
