from dataclasses import dataclass, field
from decimal import Decimal
from statistics import median
from typing import Iterable, Mapping

from relife_eurostat.datasets import EU_AGGREGATE
from relife_eurostat.models import Observation, QualityFlag

DimensionsKey = tuple[tuple[str, str], ...]

# Modified z-score constants from Iglewicz & Hoaglin (1993)
_Z_SCALE = Decimal("0.6745")
_Z_THRESHOLD = Decimal("3.5")


@dataclass
class _Group:
    """One combination of the dimensions other than geo, in the two newest periods."""

    dataset_code: str
    dimensions: Mapping[str, str]
    previous: dict[str, Decimal | None] = field(default_factory=dict)
    newest: dict[str, Decimal | None] = field(default_factory=dict)


def check_quality(observations: Iterable[Observation]) -> list[QualityFlag]:
    """Flag suspicious values in the newest period of one dataset.

    Only the newest period is checked, so a first full load raises no more
    flags than any later run.
    """

    observations = list(observations)
    periods = sorted({observation.period for observation in observations})

    if len(periods) < 2:
        return []

    previous_period, newest_period = periods[-2:]
    groups: dict[DimensionsKey, _Group] = {}

    for observation in observations:
        if observation.period not in (previous_period, newest_period):
            continue

        key = tuple(sorted(observation.dimensions.items()))
        group = groups.setdefault(
            key, _Group(observation.dataset_code, observation.dimensions)
        )
        values = group.newest if observation.period == newest_period else group.previous
        values[observation.geo] = observation.value

    flags: list[QualityFlag] = []

    for group in groups.values():
        flags.extend(_completeness(group, previous_period, newest_period))
        flags.extend(_outliers(group, previous_period, newest_period))

    return flags


def _completeness(
    group: _Group, previous_period: str, newest_period: str
) -> list[QualityFlag]:
    return [
        QualityFlag(
            dataset_code=group.dataset_code,
            dimensions=group.dimensions,
            geo=geo,
            period=newest_period,
            check="completeness",
            reason=(
                f"{geo} had {previous} in {previous_period} "
                f"but has no value in {newest_period}"
            ),
        )
        for geo, previous in sorted(group.previous.items())
        if previous is not None and group.newest.get(geo) is None
    ]


def _outliers(
    group: _Group, previous_period: str, newest_period: str
) -> list[QualityFlag]:
    # Relative change per country, comparable across different price levels.
    # The EU aggregate is an average of the countries, not a peer of them.
    changes = {
        geo: (newest - previous) / previous
        for geo, previous in group.previous.items()
        if geo != EU_AGGREGATE
        and previous
        and (newest := group.newest.get(geo)) is not None
    }

    if not changes:
        return []

    center = median(changes.values())
    mad = median(abs(change - center) for change in changes.values())

    # Half or more of the changes are identical: the score is undefined
    if mad == 0:
        return []

    flags: list[QualityFlag] = []

    for geo, change in sorted(changes.items()):
        score = _Z_SCALE * (change - center) / mad

        if abs(score) <= _Z_THRESHOLD:
            continue

        flags.append(
            QualityFlag(
                dataset_code=group.dataset_code,
                dimensions=group.dimensions,
                geo=geo,
                period=newest_period,
                check="outlier",
                reason=(
                    f"{geo} changed {change:+.1%} from {group.previous[geo]} in "
                    f"{previous_period} to {group.newest[geo]} in {newest_period} "
                    f"(modified z-score {score:.1f}; "
                    f"median change across countries {center:+.1%})"
                ),
            )
        )

    return flags
