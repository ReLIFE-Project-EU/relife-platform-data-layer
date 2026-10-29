import argparse
import logging
import os
import sys
from typing import Sequence

from supabase import create_client

from relife_eurostat.datasets import DATASETS, Dataset
from relife_eurostat.evaluate import Evaluation, evaluate
from relife_eurostat.fetch import fetch
from relife_eurostat.store import Store

_logger = logging.getLogger(__name__)


def _plan(datasets: Sequence[Dataset], store: Store) -> Evaluation:
    total = Evaluation()

    for dataset in datasets:
        fetched = fetch(dataset)
        result = evaluate(stored=store.latest(dataset.code), fetched=fetched)

        print(
            f"{dataset.code}: fetched {len(fetched)} values, "
            f"{len(result.new)} new, {len(result.changed)} changed"
        )

        total.new.extend(result.new)
        total.changed.extend(result.changed)

    print(f"Total: {len(total.new)} new, {len(total.changed)} changed")

    return total


def sync(datasets: Sequence[Dataset], store: Store, apply: bool) -> None:
    if not apply:
        _plan(datasets, store)
        print("Dry run: nothing was written. Pass --apply to store the values.")
        return

    run_id = store.start_run()
    _logger.info("Started run %s", run_id)

    try:
        # Plan every dataset before writing any, so a failed download
        # writes nothing
        result = _plan(datasets, store)
        store.insert_observations(run_id, result.new + result.changed)
        store.succeed_run(run_id, len(result.new), len(result.changed))
    except Exception as exc:
        try:
            store.fail_run(run_id, f"{type(exc).__name__}: {exc}")
        except Exception:
            # Keep the original error as the cause; the run stays running
            _logger.exception("Could not mark run %s as failed", run_id)

        raise

    print(f"Run {run_id} succeeded")


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

    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )

    args = _parse_args(argv)

    try:
        sync(DATASETS, _create_store(), apply=args.apply)
    except Exception:
        _logger.exception("Sync failed")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
