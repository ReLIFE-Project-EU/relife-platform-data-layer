from dataclasses import dataclass, field
from typing import Iterable

from relife_eurostat.models import Observation, QualityFlag
from relife_eurostat.quality import check_quality


@dataclass
class Evaluation:
    new: list[Observation] = field(default_factory=list)
    changed: list[Observation] = field(default_factory=list)
    flags: list[QualityFlag] = field(default_factory=list)


def evaluate(
    stored: Iterable[Observation], fetched: Iterable[Observation]
) -> Evaluation:
    """Compare freshly fetched values for one dataset against the stored latest values.

    Also flags suspicious values in the newest fetched period for review.
    """

    fetched = list(fetched)
    latest = {observation.key: observation for observation in stored}
    result = Evaluation(flags=check_quality(fetched))

    for observation in fetched:
        previous = latest.get(observation.key)

        if previous is None:
            result.new.append(observation)
        elif (previous.value, previous.flag) != (observation.value, observation.flag):
            result.changed.append(observation)

    return result
