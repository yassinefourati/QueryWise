FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt requirements-connectors.txt ./
RUN pip install --no-cache-dir -r requirements.txt
# Optional connector drivers, e.g. --build-arg CONNECTORS="PyMySQL==1.2.3 pymongo==4.18.3 duckdb==1.5.6 openpyxl==3.1.5"
ARG CONNECTORS=""
RUN if [ -n "$CONNECTORS" ]; then pip install --no-cache-dir $CONNECTORS; fi
COPY backend ./backend
COPY scripts/seed.py ./scripts/seed.py
COPY dist ./dist
COPY pack ./pack
# /app/state is the only writable app path; compose mounts a named volume there (app-state DB + key file).
RUN python scripts/seed.py && useradd --create-home appuser && mkdir -p /app/state && chown -R appuser:appuser /app/state && chmod 700 /app/state
USER appuser
ENV QUERYWISE_STATE_DIR=/app/state
EXPOSE 8000
CMD ["uvicorn", "backend.main:app", "--host", "0.0.0.0", "--port", "8000"]
