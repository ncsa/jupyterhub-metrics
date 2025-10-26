# Build stage
FROM alpine:3.22 AS kubectl-builder
RUN apk add --no-cache curl
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /kubectl

# Runtime stage
FROM alpine:3.22

# Install runtime dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    postgresql-client \
    ca-certificates

# Copy kubectl from builder stage
COPY --from=kubectl-builder /kubectl /usr/local/bin/kubectl

# Create non-root user for running the collector
RUN addgroup -g 65534 nobody || true && \
    adduser -D -u 65534 -G nobody nobody || true

# Set working directory
WORKDIR /scripts

# Copy collector script
COPY collector.sh /scripts/collector.sh
RUN chmod +x /scripts/collector.sh

# Switch to non-root user
USER 65534

# Run the collector
ENTRYPOINT ["/bin/bash", "/scripts/collector.sh"]
