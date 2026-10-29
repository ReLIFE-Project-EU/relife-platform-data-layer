from dataclasses import dataclass
from decimal import Decimal
from typing import Literal, Mapping

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


QualityCheck = Literal["completeness", "outlier"]


@dataclass(frozen=True)
class QualityFlag:
    """A suspicious value, or a missing one, in a series and period for a person to review."""

    dataset_code: str
    dimensions: Mapping[str, str]
    geo: str
    period: str
    check: QualityCheck
    # Short human-readable explanation shown to the reviewer
    reason: str
