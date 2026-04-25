# syntax=docker/dockerfile:1.6
FROM golang:1.22-alpine AS builder
WORKDIR /workspace
COPY go.work ./
COPY shared/ shared/
COPY frontend/ frontend/
RUN cd frontend && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/frontend .

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /out/frontend /app/frontend
COPY --from=builder /workspace/frontend/templates/ /app/templates/
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/frontend"]
