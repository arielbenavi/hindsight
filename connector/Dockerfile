# hindsight connector (Muse MCP + /ingest + /saves). Data lives in /data (a volume).
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir mcp uvicorn
COPY server.py .
ENV HINDSIGHT_CONNECTOR_DATA=/data PORT=8765
EXPOSE 8765
# Listen on all interfaces inside the container (server.py's default is localhost).
CMD ["python", "-c", "import os, uvicorn, server; uvicorn.run(server.RequestLog(server.app), host='0.0.0.0', port=int(os.environ['PORT']), log_level='warning')"]
