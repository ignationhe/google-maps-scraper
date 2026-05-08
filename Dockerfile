# Build stage for Playwright dependencies
FROM ubuntu:20.04 AS playwright-deps
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/browsers
#ENV PLAYWRIGHT_DRIVER_PATH=/opt/
ARG TARGETARCH

RUN export PATH=$PATH:/usr/local/go/bin:/root/go/bin \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl wget \
    # Architektur-Logik für den Go-Download
    && if [ "$TARGETARCH" = "arm64" ]; then \
         GO_ARCH="arm64"; \
       else \
         GO_ARCH="amd64"; \
       fi \
    && wget -q "https://go.dev/dl/go1.22.5.linux-${GO_ARCH}.tar.gz" \
    && tar -C /usr/local -xzf "go1.22.5.linux-${GO_ARCH}.tar.gz" \
    && rm "go1.22.5.linux-${GO_ARCH}.tar.gz" \
    # ... (Rest des ursprünglichen RUN-Befehls: Nodejs, Playwright, etc.)
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && go install github.com/playwright-community/playwright-go/cmd/playwright@latest \
    && mkdir -p /opt/browsers \
    && playwright install chromium --with-deps

# Build stage
# NOTE: using 1.22 as it matches the go.mod requirement and is a stable release
FROM golang:1.22.5-bookworm AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# Build with version info stripped to reduce binary size
RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o /usr/bin/google-maps-scraper

# Final stage
FROM debian:bookworm-slim
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/browsers
ENV PLAYWRIGHT_DRIVER_PATH=/opt
# Run as non-root user for better security
# Using UID 1001 to avoid conflicts with common system users
RUN useradd -m -u 1001 -s /bin/bash scraper

# Install only the necessary dependencies in a single layer
# Note: libglib2.0-0 added to fix missing dependency warning on some systems
# Note: libxshmfence1 added to fix occasional shared memory fence errors with Chromium
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libglib2.0-0 \
    libnss3 \
    libnspr4 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libatspi2.0-0 \
    libx11-6 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2 \
    libxshmfence1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=playwright-deps /opt/browsers /opt/browsers
COPY --from=playwright-deps /root/.cache/ms-playwright-go /opt/ms-playwright-go

RUN chmod -R 755 /opt/browsers \
    && chmod -R 755 /opt/ms-playwright-go

COPY --from=builder /usr/bin/google-maps-scraper /usr/bin/

USER scraper

ENTRYPOINT ["google-maps-scraper"]
