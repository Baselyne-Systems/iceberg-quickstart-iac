FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

COPY pyproject.toml uv.lock ./
COPY lakehouse/ lakehouse/

RUN uv export --frozen --no-hashes > requirements.txt && \
    uv pip install --system -r requirements.txt && \
    rm requirements.txt

RUN useradd -m dagster && chown -R dagster:dagster /app
USER dagster

EXPOSE 3000

CMD ["dagster-webserver", "-h", "0.0.0.0", "-p", "3000"]
