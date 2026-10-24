# LeadWise AI loader.
#
# Build:
#   docker build -t leadwise-loader .
#
# Run (profile = website | rag | master; schema and data mounted):
#   docker run --rm \
#     -e WEBSITE_DATABASE_URL=postgresql://... \
#     -e WEBSITE_DATA_ROOT=/data \
#     -e WEBSITE_SCHEMA_ROOT=/schema \
#     -v /path/to/data/website:/data \
#     -v /path/to/schema/website:/schema \
#     leadwise-loader load leadwise-ai/60-instance.json --profile website --commit

FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .

ENTRYPOINT ["python", "-m", "loader"]
CMD ["--help"]
