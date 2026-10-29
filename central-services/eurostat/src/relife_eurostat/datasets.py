from dataclasses import dataclass

EU27_GEOS = (
    "AT",
    "BE",
    "BG",
    "CY",
    "CZ",
    "DE",
    "DK",
    "EE",
    "EL",
    "ES",
    "FI",
    "FR",
    "HR",
    "HU",
    "IE",
    "IT",
    "LT",
    "LU",
    "LV",
    "MT",
    "NL",
    "PL",
    "PT",
    "RO",
    "SE",
    "SI",
    "SK",
)

EU_AGGREGATE = "EU27_2020"

# Cyprus and Malta have no natural gas grid: nrg_pc_202 lacks both codes, and
# Eurostat rejects a whole query that names a code a dataset does not have
GAS_GEOS = tuple(geo for geo in EU27_GEOS if geo not in {"CY", "MT"})


@dataclass(frozen=True)
class Dataset:
    code: str
    # SDMX series key, dimensions separated by "." and alternatives by "+"
    key: str
    start_period: str


def _series_key(*dimensions: str, geos: tuple[str, ...]) -> str:
    # geo is the last dimension before time in every dataset below
    return ".".join([*dimensions, "+".join(geos + (EU_AGGREGATE,))])


DATASETS = (
    # Household electricity prices, half-yearly
    # freq.siec.nrg_cons.unit.tax.currency.geo
    Dataset(
        code="nrg_pc_204",
        key=_series_key(
            "S", "E7000", "KWH2500-4999", "KWH", "I_TAX", "EUR", geos=EU27_GEOS
        ),
        start_period="2015",
    ),
    # Household natural gas prices, half-yearly, band D2 (20-199 GJ)
    # freq.siec.nrg_cons.unit.tax.currency.geo
    Dataset(
        code="nrg_pc_202",
        key=_series_key("S", "G3000", "GJ20-199", "KWH", "I_TAX", "EUR", geos=GAS_GEOS),
        start_period="2015",
    ),
    # Heating degree days, yearly, HDD indicator only (not CDD)
    # freq.unit.indic_nrg.geo
    Dataset(
        code="nrg_chdd_a",
        key=_series_key("A", "NR", "HDD", geos=EU27_GEOS),
        start_period="2015",
    ),
)
