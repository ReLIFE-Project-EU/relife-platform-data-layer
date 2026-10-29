import argparse
import logging
import os
import sys
from dataclasses import dataclass, field
from typing import Protocol, Sequence

from supabase import create_client

from relife_eurostat.datasets import DATASETS, Dataset
from relife_eurostat.evaluate import Evaluation, evaluate
from relife_eurostat.fetch import Eurostat, EurostatError
from relife_eurostat.models import Observation, QualityFlag, RunSummary
from relife_eurostat.store import Store

_logger = logging.getLogger(__name__)


class SyncStore(Protocol):
    def latest(self, dataset_code: str) -> list[Observation]: ...

    def last_data_change(self, dataset_code: str) -> str | None: ...

    def start_run(self) -> str: ...

    def insert_observations(
        self, run_id: str, observations: Sequence[Observation]
    ) -> None: ...

    def insert_flags(self, run_id: str, flags: Sequence[QualityFlag]) -> int: ...

    def succeed_run(self, run_id: str, summary: RunSummary) -> None: ...

    def fail_run(self, run_id: str, error: str) -> None: ...


class EurostatSource(Protocol):
    def inventory(self) -> dict[str, str]: ...

    def fetch(self, dataset: Dataset) -> list[Observation]: ...


@dataclass
class _Plan:
    evaluation: Evaluation = field(default_factory=Evaluation)
    # "Last data change" seen per dataset code
    datasets: dict[str, str] = field(default_factory=dict)
    has_new_data: bool = False

    def summary(self) -> RunSummary:
        return RunSummary(
            added_count=len(self.evaluation.new),
            changed_count=len(self.evaluation.changed),
            flag_count=len(self.evaluation.flags),
            datasets=self.datasets,
            has_new_data=self.has_new_data,
        )


def _plan(
    datasets: Sequence[Dataset],
    store: SyncStore,
    eurostat: EurostatSource,
    force: bool,
) -> _Plan:
    inventory = eurostat.inventory()

    # A renamed or retired dataset would otherwise go quietly stale, and an
    # empty "Last data change" would be recorded and then never differ
    missing = [dataset.code for dataset in datasets if not inventory.get(dataset.code)]

    if missing:
        raise EurostatError(
            f"Datasets missing from the Eurostat inventory or without a "
            f"last data change: {missing}"
        )

    plan = _Plan()
    total = plan.evaluation

    for dataset in datasets:
        last_change = inventory[dataset.code]
        changed = last_change != store.last_data_change(dataset.code)
        plan.datasets[dataset.code] = last_change
        plan.has_new_data = plan.has_new_data or changed

        if not changed and not force:
            print(f"{dataset.code}: no data change since {last_change}, skipped")
            continue

        fetched = eurostat.fetch(dataset)
        result = evaluate(stored=store.latest(dataset.code), fetched=fetched)

        print(
            f"{dataset.code}: fetched {len(fetched)} values, "
            f"{len(result.new)} new, {len(result.changed)} changed, "
            f"{len(result.flags)} flagged"
        )

        for flag in result.flags:
            print(f"  [{flag.check}] {flag.reason}")

        total.new.extend(result.new)
        total.changed.extend(result.changed)
        total.flags.extend(result.flags)

    print(
        f"Total: {len(total.new)} new, {len(total.changed)} changed, "
        f"{len(total.flags)} flagged"
    )

    return plan


def sync(
    datasets: Sequence[Dataset],
    store: SyncStore,
    eurostat: EurostatSource,
    apply: bool,
    dataset_code: str | None = None,
) -> None:
    """Sync the datasets; with dataset_code, sync only that one even if it has not changed."""

    force = dataset_code is not None

    if dataset_code is not None:
        datasets = [dataset for dataset in datasets if dataset.code == dataset_code]

        if not datasets:
            raise ValueError(f"Unknown dataset {dataset_code!r}")

    if not apply:
        _plan(datasets, store, eurostat, force)
        print(
            "Dry run: nothing was written. "
            "Pass --apply to store the values and flags."
        )
        return

    run_id = store.start_run()
    _logger.info("Started run %s", run_id)

    try:
        # Plan every dataset before writing any, so a failed download
        # writes nothing
        plan = _plan(datasets, store, eurostat, force)
        result = plan.evaluation
        store.insert_observations(run_id, result.new + result.changed)
        new_flag_count = store.insert_flags(run_id, result.flags)
        store.succeed_run(run_id, plan.summary())
    except Exception as exc:
        try:
            store.fail_run(run_id, f"{type(exc).__name__}: {exc}")
        except Exception:
            # Keep the original error as the cause; the run stays running
            _logger.exception("Could not mark run %s as failed", run_id)

        raise

    print(
        f"Run {run_id} succeeded: {new_flag_count} new flags to review, "
        f"{len(result.flags) - new_flag_count} already in the review list"
    )


def _create_store() -> Store:
    try:
        url = os.environ["SUPABASE_URL"]
        key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    except KeyError as exc:
        raise RuntimeError(f"Missing environment variable {exc}") from exc

    return Store(create_client(url, key))


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="relife-eurostat",
        description="Sync Eurostat datasets into the ReLIFE central Supabase",
    )

    commands = parser.add_subparsers(dest="command", required=True)

    sync_parser = commands.add_parser(
        "sync", help="Fetch Eurostat values and store new and changed ones"
    )

    sync_parser.add_argument(
        "--apply",
        action="store_true",
        help="Write to Supabase; without it, only print what would be written",
    )

    sync_parser.add_argument(
        "--dataset",
        metavar="CODE",
        help="Process only this dataset, even if Eurostat has not changed it",
    )

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    args = _parse_args(argv)

    try:
        sync(
            DATASETS,
            _create_store(),
            Eurostat(),
            apply=args.apply,
            dataset_code=args.dataset,
        )
    except Exception:
        _logger.exception("Sync failed")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
