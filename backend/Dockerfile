FROM python:3.12-slim

# Unbuffered stdout/stderr so app logs (uvicorn startup, tracebacks) show up in
# the platform's deploy logs immediately instead of being buffered/lost.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY enhale_backend ./enhale_backend

# Bind to the platform-provided $PORT (Railway/Render set it); fall back to 8000.
# `exec` so uvicorn becomes PID 1 and receives SIGTERM directly (clean shutdown).
CMD ["sh", "-c", "exec uvicorn enhale_backend.api.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
