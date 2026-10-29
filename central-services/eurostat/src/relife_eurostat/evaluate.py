from dataclasses import dataclass, field
from typing import Iterable

from relife_eurostat.models import Observation


@dataclass
class Evaluation:
    new: list[Observation] = field(default_factory=list)
    changed: list[Observation] = field(default_factory=list)


def evaluate(
    stored: Iterable[Observation], fetched: Iterable[Observation]
) -> Evaluation:
    """Compare freshly fetched values for one dataset against the stored latest values."""

    latest = {observation.key: observation for observation in stored}
    result = Evaluation()

    for observation in fetched:
        previous = latest.get(observation.key)

        if previous is None:
            result.new.append(observation)
        elif (previous.value, previous.flag) != (observation.value, observation.flag):
            result.changed.append(observation)

    return result
