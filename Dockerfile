FROM golang:1.21-alpine

WORKDIR /app

# Install necessary system packages
RUN apk add --no-cache \
    linux-headers \
    gcc \
    musl-dev

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go build -o node-metrics-exporter .

# Add necessary capabilities
RUN apk add --no-cache libc6-compat

CMD ["./node-metrics-exporter", "-config=/var/lib/vpn-metrics/config.json"] 