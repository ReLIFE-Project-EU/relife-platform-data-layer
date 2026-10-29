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


# Changes of +1.7% to +2.3% from 0.2000: median 2.05, MAD 0.2
SIMILAR_NEWEST = {
    "AT": "0.2034",
    "BE": "0.2036",
    "DE": "0.2038",
    "ES": "0.2040",
    "FR": "0.2042",
    "NL": "0.2044",
    "PT": "0.2046",
}


def two_periods(newest: dict[str, str]) -> list[Observation]:
    """Every geo at 0.2000 in 2025-S1, then at the given value in 2025-S2."""

    return [obs(geo, "2025-S1", "0.2000") for geo in newest] + [
        obs(geo, "2025-S2", value) for geo, value in newest.items()
    ]


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


def test_country_missing_from_newest_period_gets_completeness_flag() -> None:
    fetched = [
        obs("ES", "2025-S1", "0.2500"),
        obs("FR", "2025-S1", "0.2600"),
        obs("PT", "2025-S1", "0.2400"),
        obs("ES", "2025-S2", "0.2510"),
        obs("FR", "2025-S2", "0.2610"),
    ]

    result = evaluate(stored=[], fetched=fetched)

    assert [(f.geo, f.period, f.check) for f in result.flags] == [
        ("PT", "2025-S2", "completeness")
    ]
    assert result.flags[0].dimensions == DIMENSIONS
    assert "PT" in result.flags[0].reason


def test_one_extreme_change_among_similar_ones_gets_one_outlier_flag() -> None:
    fetched = two_periods({**SIMILAR_NEWEST, "IT": "0.3200"})

    result = evaluate(stored=[], fetched=fetched)

    assert [(f.geo, f.period, f.check) for f in result.flags] == [
        ("IT", "2025-S2", "outlier")
    ]
    assert "+60" in result.flags[0].reason


def test_eu_aggregate_with_extreme_change_gets_no_flag() -> None:
    fetched = two_periods({**SIMILAR_NEWEST, "EU27_2020": "0.3200"})

    result = evaluate(stored=[], fetched=fetched)

    assert result.flags == []


def test_period_where_mad_is_zero_gets_no_outlier_flag() -> None:
    # Most prices unchanged, so the median absolute deviation is 0
    unchanged = {geo: "0.2000" for geo in SIMILAR_NEWEST}
    fetched = two_periods({**unchanged, "IT": "0.3200"})

    result = evaluate(stored=[], fetched=fetched)

    assert result.flags == []
