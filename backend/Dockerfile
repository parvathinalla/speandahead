FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

WORKDIR /app
COPY backend/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Source files only; no local .env, sandbox seed or account mappings in image.
COPY backend/*.py /app/
COPY backend/scripts /app/scripts

RUN useradd --system --uid 10001 --create-home creditpilot && \
    mkdir -p /app/private && \
    chown -R creditpilot:creditpilot /app/private
USER creditpilot

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
