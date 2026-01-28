# ===== Build Stage =====
FROM astral/uv:python3.12-trixie AS builder

# Set working directory
WORKDIR /app

# Copy dependency files first for better layer caching
COPY pyproject.toml uv.lock ./

# Install dependencies
RUN uv sync --frozen --no-dev

# Copy source code
COPY wyoming_supertonic/ ./wyoming_supertonic/

# Download model data (this will be cached if unchanged)
RUN uv add huggingface-hub && \
  uv run hf download Supertone/supertonic-2 --local-dir supertonic-data && \
  uv remove huggingface-hub

# ===== Runtime Stage =====
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS runtime
# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  curl \
  && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd --create-home --shell /bin/bash wyoming

# Set working directory
WORKDIR /app

# Copy project files
COPY --from=builder /app/pyproject.toml /app/pyproject.toml
COPY --from=builder /app/uv.lock /app/uv.lock
COPY --from=builder /app/wyoming_supertonic /app/wyoming_supertonic

# Copy virtual environment from builder
COPY --from=builder /app/.venv /app/.venv

# Copy model data
COPY --from=builder /app/supertonic-data /app/supertonic-data

# Set ownership
RUN chown -R wyoming:wyoming /app

# Switch to non-root user
USER wyoming

# Configure UV environment
ENV UV_VENV=/app/.venv
ENV PATH="/app/.venv/bin:$PATH"

# Expose default port
EXPOSE 10209

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD uv run curl -f http://localhost:10209/info || exit 1

# Default environment variables
ENV SUPERTONIC_DATA_DIR=/app/supertonic-data
ENV SUPERTONIC_URI=tcp://0.0.0.0:10209
ENV SUPERTONIC_SPEED=1.0
ENV SUPERTONIC_STEPS=5
ENV SUPERTONIC_THREADS=4

# Default command
CMD ["uv", "run", "python", "-m", "wyoming_supertonic", "--data-dir", "/app/supertonic-data", "--uri", "tcp://0.0.0.0:10209"]
