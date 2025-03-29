FROM golang:1.21-alpine

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN go build -o node-metrics-exporter .

# Create directory for config
RUN mkdir -p /var/lib/vpn-metrics

CMD ["./node-metrics-exporter", "-config=/var/lib/vpn-metrics/config.json"] 