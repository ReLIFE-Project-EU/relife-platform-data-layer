from dataclasses import dataclass
from decimal import Decimal
from typing import Mapping

SeriesPeriodKey = tuple[str, tuple[tuple[str, str], ...], str, str]


@dataclass(frozen=True)
class Observation:
    """One Eurostat value for a series (dataset + dimensions + geo) and period."""

    dataset_code: str
    # Every SDMX dimension except geo and time, e.g. {"freq": "S", "tax": "I_TAX"}
    dimensions: Mapping[str, str]
    geo: str
    period: str
    # None when Eurostat publishes the observation without a value
    value: Decimal | None
    # Eurostat observation flag, e.g. "p" (provisional); None when final
    flag: str | None

    @property
    def key(self) -> SeriesPeriodKey:
        return (
            self.dataset_code,
            tuple(sorted(self.dimensions.items())),
            self.geo,
            self.period,
        )
