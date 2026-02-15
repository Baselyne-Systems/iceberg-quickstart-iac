FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml .
COPY lakehouse/ lakehouse/

RUN pip install --no-cache-dir -e ".[dev]"

RUN useradd -m dagster && chown -R dagster:dagster /app
USER dagster

EXPOSE 3000

CMD ["dagster-webserver", "-h", "0.0.0.0", "-p", "3000"]
