from decimal import Decimal

from relife_eurostat.evaluate import evaluate
from relife_eurostat.models import Observation

DIMENSIONS = {
    "freq": "S",
    "siec": "E7000",
    "nrg_cons": "KWH2500-4999",
    "unit": "KWH",
    "tax": "I_TAX",
    "currency": "EUR",
}


def obs(
    geo: str, period: str, value: str | None, flag: str | None = None
) -> Observation:
    return Observation(
        dataset_code="nrg_pc_204",
        dimensions=DIMENSIONS,
        geo=geo,
        period=period,
        value=None if value is None else Decimal(value),
        flag=flag,
    )


def test_first_load_everything_is_new() -> None:
    fetched = [
        obs("ES", "2015-S1", "0.2309"),
        obs("ES", "2015-S2", "0.237"),
        obs("MT", "2015-S1", None, "c"),
    ]

    result = evaluate(stored=[], fetched=fetched)

    assert result.new == fetched
    assert result.changed == []


def test_same_data_again_nothing_is_new_or_changed() -> None:
    stored = [
        obs("ES", "2015-S1", "0.2309"),
        obs("ES", "2015-S2", "0.2370"),
        obs("MT", "2015-S1", None, "c"),
    ]
    fetched = [
        obs("ES", "2015-S1", "0.2309"),
        obs("ES", "2015-S2", "0.237"),
        obs("MT", "2015-S1", None, "c"),
    ]

    result = evaluate(stored=stored, fetched=fetched)

    assert result.new == []
    assert result.changed == []


def test_revised_value_and_flag_only_change_both_count_as_changed() -> None:
    stored = [
        obs("ES", "2024-S2", "0.2512"),
        obs("MT", "2024-S2", "0.1300", "p"),
        obs("MT", "2025-S1", "0.1290"),
    ]
    revised_value = obs("ES", "2024-S2", "0.2498")
    flag_finalised = obs("MT", "2024-S2", "0.13")
    unchanged = obs("MT", "2025-S1", "0.1290")
    added = obs("MT", "2025-S2", "0.1310", "p")

    result = evaluate(
        stored=stored,
        fetched=[revised_value, flag_finalised, unchanged, added],
    )

    assert result.changed == [revised_value, flag_finalised]
    assert result.new == [added]
