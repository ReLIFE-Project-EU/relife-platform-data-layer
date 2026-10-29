import csv
import gzip
import io
import logging
from decimal import Decimal, InvalidOperation

import httpx

from relife_eurostat.datasets import Dataset
from relife_eurostat.models import Observation

_logger = logging.getLogger(__name__)

SDMX_DATA_URL = "https://ec.europa.eu/eurostat/api/dissemination/sdmx/2.1/data"
TIMEOUT_SECONDS = 120

_GZIP_MAGIC = b"\x1f\x8b"
_ASYNC_STUB_MARKER = "<env:Envelope"

# SDMX-CSV columns that are not series dimensions
_GEO = "geo"
_TIME_PERIOD = "TIME_PERIOD"
_OBS_VALUE = "OBS_VALUE"
_OBS_FLAG = "OBS_FLAG"
_NON_DIMENSION_COLUMNS = {
    "DATAFLOW",
    "LAST UPDATE",
    _GEO,
    _TIME_PERIOD,
    _OBS_VALUE,
    _OBS_FLAG,
    "CONF_STATUS",
}


class EurostatError(Exception):
    pass


def fetch(dataset: Dataset) -> list[Observation]:
    url = f"{SDMX_DATA_URL}/{dataset.code}/{dataset.key}"

    params = {
        "format": "SDMX-CSV",
        "compressed": "true",
        "startPeriod": dataset.start_period,
    }

    _logger.info("Fetching %s from %s", dataset.code, url)
    response = httpx.get(url, params=params, timeout=TIMEOUT_SECONDS)
    response.raise_for_status()

    return parse_sdmx_csv(dataset.code, _decode(response.content))


def _decode(content: bytes) -> str:
    # compressed=true returns a gzipped file body, not a Content-Encoding
    if content.startswith(_GZIP_MAGIC):
        content = gzip.decompress(content)

    text = content.decode("utf-8-sig")

    # Eurostat answers large requests asynchronously with a SOAP envelope
    # pointing to a job, instead of the data itself
    if text.lstrip().startswith(_ASYNC_STUB_MARKER):
        raise EurostatError(
            "Eurostat returned an asynchronous job stub instead of data; "
            "the request is too large to be served synchronously"
        )

    return text


def parse_sdmx_csv(dataset_code: str, text: str) -> list[Observation]:
    reader = csv.DictReader(io.StringIO(text))
    fieldnames = reader.fieldnames or []

    missing = {_GEO, _TIME_PERIOD, _OBS_VALUE, _OBS_FLAG} - set(fieldnames)

    if missing:
        raise EurostatError(f"SDMX-CSV response lacks columns: {sorted(missing)}")

    dimension_columns = [
        name for name in fieldnames if name not in _NON_DIMENSION_COLUMNS
    ]

    return [
        Observation(
            dataset_code=dataset_code,
            dimensions={name: row[name] for name in dimension_columns},
            geo=row[_GEO],
            period=row[_TIME_PERIOD],
            value=_parse_value(row[_OBS_VALUE]),
            flag=row[_OBS_FLAG] or None,
        )
        for row in reader
    ]


def _parse_value(raw: str) -> Decimal | None:
    if not raw.strip():
        return None

    try:
        return Decimal(raw)
    except InvalidOperation as exc:
        raise EurostatError(f"Invalid observation value: {raw!r}") from exc
