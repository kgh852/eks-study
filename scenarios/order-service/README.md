# order-service

REST API 기반 주문 관리 서비스. Part 2~3 실습에서 K8s Deployment, HPA, Karpenter 스케일링 시연에 사용.

## 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| `POST` | `/orders` | 주문 생성 |
| `GET` | `/orders/:id` | 주문 조회 |
| `GET` | `/healthz` | 헬스체크 |
| `GET` | `:9090/metrics` | Prometheus 메트릭 |

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `PORT` | `8080` | HTTP 리스너 포트 |

## 로컬 실행

```bash
go run .
# 다른 터미널에서:
curl -X POST http://localhost:8080/orders \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"u1","amount":1000}'
```

## 테스트

```bash
go test ./...
```

## 도커 빌드 (scenarios/ 루트에서)

```bash
docker build -t eks-study/order-service:latest -f order-service/Dockerfile ..
```

## Part 3 KEDA 스케일 트리거

- HTTP RPS (Prometheus 메트릭 기반)
- CPU 사용률
