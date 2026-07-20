FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY enhale_backend ./enhale_backend

EXPOSE 8000
CMD ["uvicorn", "enhale_backend.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
