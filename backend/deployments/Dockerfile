FROM golang:alpine AS builder

WORKDIR /build

COPY go.mod go.sum ./

RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o /app/cove ./cmd/main.go

FROM alpine:latest

WORKDIR /app

COPY --from=builder /app/cove .

EXPOSE 3425

CMD ["./cove"]
