# LeadWise AI loader.
#
# Build:
#   docker build -t leadwise-loader .
#
# Run (schema and data mounted at runtime):
#   docker run --rm \
#     -e DATABASE_URL=postgres://... \
#     -v /path/to/lead-wise-ai-data:/data \
#     -v /path/to/lead-wise-ai-schema:/schema \
#     -e LW_DATA_ROOT=/data \
#     -e LW_SCHEMA_ROOT=/schema \
#     leadwise-loader clients/leadwise-ai/60-instance.json --commit

FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ ./src/
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .

ENTRYPOINT ["python", "-m", "loader"]
CMD ["--help"]