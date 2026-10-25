FROM ghcr.io/astral-sh/uv:0.13.5@sha256:32a7bb39b496babbd997b0a39a4d66c126bdaf5661b302bf6f06abda8deca6ff AS uv

FROM node:24.15.0-bookworm-slim@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY index.html vite.config.js ./
COPY public ./public
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:24.15.0-bookworm-slim@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d AS agent-build
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_PYTHON_INSTALL_DIR=/opt/python UV_PROJECT_ENVIRONMENT=/opt/venv UV_LINK_MODE=copy UV_PYTHON_PREFERENCE=only-managed
WORKDIR /app
COPY pyproject.toml uv.lock .python-version ./
COPY src/agent/fios_agent ./src/agent/fios_agent
RUN uv python install 3.11.17 && uv sync --frozen --no-editable --no-dev --python 3.11.17

FROM node:24.15.0-bookworm-slim@sha256:4e6b70dd6cbfc88c8157ba19aa3d9f9cce6ba4703576d55459e45efcbc9c5f5d
ENV NODE_ENV=production PORT=3000 DB_PATH=/app/data/fios.sqlite \
    FIOS_AGENT_PYTHON=/opt/venv/bin/python PYTHONDONTWRITEBYTECODE=1 \
    PYDANTIC_AI_NO_BANNER=1 UV_PYTHON_DOWNLOADS=never
WORKDIR /app
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/dist ./dist
COPY --from=agent-build /opt/python /opt/python
COPY --from=agent-build /opt/venv /opt/venv
COPY --chown=node:node package.json ./
COPY --chown=node:node server ./server
COPY --chown=node:node src/agent ./src/agent
COPY --chown=node:node scripts/observe-hosts.mjs ./scripts/observe-hosts.mjs
RUN mkdir -p /app/data && chown node:node /app/data
USER node
EXPOSE 3000
CMD ["node", "server/index.js"]
