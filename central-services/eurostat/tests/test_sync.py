from dataclasses import dataclass, field
from decimal import Decimal
from typing import Sequence

import pytest

from relife_eurostat.cli import sync
from relife_eurostat.datasets import Dataset
from relife_eurostat.fetch import EurostatError
from relife_eurostat.models import Observation, QualityFlag, RunSummary

ELECTRICITY = Dataset(code="nrg_pc_204", key="S.E7000", start_period="2015")
GAS = Dataset(code="nrg_pc_202", key="S.G3000", start_period="2015")
DATASETS = (ELECTRICITY, GAS)

INVENTORY = {
    "nrg_pc_204": "2026-10-19T23:00:00+0200",
    "nrg_pc_202": "2026-10-19T11:00:00+0200",
}


@dataclass
class Run:
    status: str = "running"
    summary: RunSummary | None = None


@dataclass
class FakeStore:
    """In-memory stand-in for the Supabase tables."""

    runs: list[Run] = field(default_factory=list)
    observations: list[Observation] = field(default_factory=list)

    def latest(self, dataset_code: str) -> list[Observation]:
        return [o for o in self.observations if o.dataset_code == dataset_code]

    def last_data_change(self, dataset_code: str) -> str | None:
        for run in reversed(self.runs):
            if run.status == "succeeded" and run.summary:
                if dataset_code in run.summary.datasets:
                    return run.summary.datasets[dataset_code]

        return None

    def start_run(self) -> str:
        self.runs.append(Run())
        return str(len(self.runs) - 1)

    def insert_observations(
        self, run_id: str, observations: Sequence[Observation]
    ) -> None:
        self.observations.extend(observations)

    def insert_flags(self, run_id: str, flags: Sequence[QualityFlag]) -> int:
        return len(flags)

    def succeed_run(self, run_id: str, summary: RunSummary) -> None:
        self.runs[int(run_id)] = Run("succeeded", summary)

    def fail_run(self, run_id: str, error: str) -> None:
        self.runs[int(run_id)].status = "failed"


@dataclass
class FakeEurostat:
    """In-memory stand-in for the Eurostat API."""

    last_changes: dict[str, str] = field(default_factory=lambda: dict(INVENTORY))
    fetched: list[str] = field(default_factory=list)

    def inventory(self) -> dict[str, str]:
        return dict(self.last_changes)

    def fetch(self, dataset: Dataset) -> list[Observation]:
        self.fetched.append(dataset.code)

        return [
            Observation(
                dataset_code=dataset.code,
                dimensions={"freq": "S"},
                geo="ES",
                period="2025-S2",
                value=Decimal("0.25"),
                flag=None,
            )
        ]


def test_second_run_without_eurostat_changes_writes_only_its_run_row() -> None:
    store, eurostat = FakeStore(), FakeEurostat()
    sync(DATASETS, store, eurostat, apply=True)
    eurostat.fetched.clear()
    stored_before = list(store.observations)

    sync(DATASETS, store, eurostat, apply=True)

    assert eurostat.fetched == []
    assert store.observations == stored_before
    assert store.runs[-1] == Run(
        "succeeded",
        RunSummary(
            added_count=0,
            changed_count=0,
            flag_count=0,
            datasets=INVENTORY,
            has_new_data=False,
        ),
    )


def test_selected_dataset_is_processed_even_without_data_change() -> None:
    store, eurostat = FakeStore(), FakeEurostat()
    sync(DATASETS, store, eurostat, apply=True)
    eurostat.fetched.clear()

    sync(DATASETS, store, eurostat, apply=True, dataset_code="nrg_pc_204")

    assert eurostat.fetched == ["nrg_pc_204"]
    summary = store.runs[-1].summary
    assert summary is not None
    assert summary.datasets == {"nrg_pc_204": "2026-10-19T23:00:00+0200"}
    assert summary.has_new_data is False


def test_unknown_dataset_code_is_an_error_before_any_run_starts() -> None:
    store, eurostat = FakeStore(), FakeEurostat()

    with pytest.raises(ValueError, match="nrg_xx_999"):
        sync(DATASETS, store, eurostat, apply=True, dataset_code="nrg_xx_999")

    assert store.runs == []
    assert eurostat.fetched == []


def test_dataset_missing_from_inventory_marks_the_run_failed() -> None:
    store, eurostat = FakeStore(), FakeEurostat()
    del eurostat.last_changes["nrg_pc_202"]

    with pytest.raises(EurostatError, match="nrg_pc_202"):
        sync(DATASETS, store, eurostat, apply=True)

    assert [run.status for run in store.runs] == ["failed"]
    assert eurostat.fetched == []


def test_only_the_dataset_with_a_new_data_change_is_downloaded() -> None:
    store, eurostat = FakeStore(), FakeEurostat()
    sync(DATASETS, store, eurostat, apply=True)
    eurostat.fetched.clear()
    eurostat.last_changes["nrg_pc_202"] = "2026-11-02T11:00:00+0100"

    sync(DATASETS, store, eurostat, apply=True)

    assert eurostat.fetched == ["nrg_pc_202"]
    summary = store.runs[-1].summary
    assert summary is not None
    assert summary.datasets == {
        "nrg_pc_204": "2026-10-19T23:00:00+0200",
        "nrg_pc_202": "2026-11-02T11:00:00+0100",
    }
    assert summary.has_new_data is True


def test_dataset_without_last_data_change_marks_the_run_failed() -> None:
    store, eurostat = FakeStore(), FakeEurostat()
    eurostat.last_changes["nrg_pc_202"] = ""

    with pytest.raises(EurostatError, match="nrg_pc_202"):
        sync(DATASETS, store, eurostat, apply=True)

    assert [run.status for run in store.runs] == ["failed"]
