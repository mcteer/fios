FROM python:3.14-slim-bookworm@sha256:e60ad028afdcdd14772a3d46decf0eaf616720f9102aeb4397a2045ff6718c3d
WORKDIR /app
COPY src/backend/__init__.py src/backend/core.py src/backend/chat_bridge.py src/backend/inventory.py src/backend/local_access.py src/backend/studio_inventory.py src/backend/wire.py backend/
COPY src/frontend/ frontend/
USER 65532:65532
CMD ["python", "-B", "-m", "backend.core", "--directory", "/observations"]
