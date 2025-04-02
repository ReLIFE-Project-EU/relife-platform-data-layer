FROM python:3.11-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir uv

COPY pyproject.toml uv.lock README.md ./
COPY src/ ./src/

RUN uv venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN uv pip install build
RUN python -m build --wheel .

FROM python:3.11-slim

WORKDIR /app

COPY --from=builder /app/dist/*.whl /app/
RUN pip install --no-cache-dir /app/*.whl

ENV API_HOST=0.0.0.0
ENV API_PORT=9090

EXPOSE 9090

CMD ["service-api"]
