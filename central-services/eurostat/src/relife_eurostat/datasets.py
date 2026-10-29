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


@dataclass(frozen=True)
class Dataset:
    code: str
    # SDMX series key, dimensions separated by "." and alternatives by "+"
    key: str
    start_period: str


HOUSEHOLD_ELECTRICITY_PRICES = Dataset(
    code="nrg_pc_204",
    key=".".join(
        [
            "S",
            "E7000",
            "KWH2500-4999",
            "KWH",
            "I_TAX",
            "EUR",
            "+".join(EU27_GEOS + ("EU27_2020",)),
        ]
    ),
    start_period="2015",
)
