FROM python:3.11-slim

COPY --from=ghcr.io/astral-sh/uv:0.10.10 /uv /bin/uv

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install dependencies first so code changes reuse the cached layer
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

COPY README.md ./
COPY src/ ./src/
RUN uv sync --frozen --no-dev --no-editable

# Stay idle: Ofelia and the manual sync task run the CLI with docker exec
CMD ["tail", "-f", "/dev/null"]
