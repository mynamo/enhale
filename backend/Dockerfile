FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY enhale_backend ./enhale_backend

# Bind to the platform-provided $PORT (Railway/Render set it); fall back to 8000
# locally. Shell form so ${PORT} is expanded at runtime.
CMD uvicorn enhale_backend.api.main:app --host 0.0.0.0 --port ${PORT:-8000}
