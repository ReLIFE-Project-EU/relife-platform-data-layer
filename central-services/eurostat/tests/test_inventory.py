import pytest

from relife_eurostat.fetch import EurostatError, parse_inventory

HEADER = (
    "Code",
    "Type",
    "Source dataset",
    "Last data change",
    "Last structural change",
    "Data download url (tsv)",
)


def tsv(*rows: tuple[str, ...]) -> str:
    return "".join("\t".join(row) + "\n" for row in rows)


def test_inventory_maps_lower_case_codes_to_last_data_change() -> None:
    text = tsv(
        HEADER,
        (
            "NRG_PC_204",
            "DATASET",
            "-",
            "2026-10-19T23:00:00+0200",
            "2026-10-05T23:00:00+0200",
            "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/NRG_PC_204/?format=TSV",
        ),
        (
            "NRG_CHDD_A",
            "DATASET",
            "-",
            "2026-05-08T11:00:00+0200",
            "2026-04-20T23:00:00+0200",
            "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data/NRG_CHDD_A/?format=TSV",
        ),
    )

    assert parse_inventory(text) == {
        "nrg_pc_204": "2026-10-19T23:00:00+0200",
        "nrg_chdd_a": "2026-05-08T11:00:00+0200",
    }


def test_inventory_without_last_data_change_column_is_an_error() -> None:
    text = tsv(("Code", "Type"), ("NRG_PC_204", "DATASET"))

    with pytest.raises(EurostatError, match="Last data change"):
        parse_inventory(text)
