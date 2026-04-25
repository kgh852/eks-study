# Scenarios — MSA 시뮬레이션 앱 (Go)

본 커리큘럼 실습에 사용되는 마이크로서비스 5종 + 공통 라이브러리.
모든 서비스는 **Go**로 작성되었으며, distroless 베이스 이미지로 빌드됩니다.

## 서비스 구성

| 서비스 | 역할 | 프로토콜 | KEDA 트리거 (Part 3) |
|--------|------|----------|----------------------|
| `order-service` | 주문 CRUD | REST (Gin, :8080) | Prometheus / CPU |
| `payment-service` | SQS 메시지 → 결제 처리 | SQS Worker | AWS SQS |
| `user-service` | 사용자 CRUD | gRPC (:50051) | CPU |
| `notification-service` | Kafka topic → 알림 발송 | Kafka Worker | Apache Kafka |
| `frontend` | SSR 페이지 | HTTP (:8080) | - |

`shared/` 모듈은 모든 서비스가 공유: `logger`, `config`, `metrics`.

## 폴더 구조

```
scenarios/
├── go.work                       # 멀티 모듈 워크스페이스
├── Makefile                      # build/test/docker/up/down
├── docker-compose.yml            # 로컬 통합 실행
├── shared/                       # 공통 라이브러리
│   ├── logger/                   # slog 기반 JSON 로거
│   ├── config/                   # 환경변수 헬퍼
│   └── metrics/                  # Prometheus 핸들러
├── order-service/
├── payment-service/
├── user-service/
├── notification-service/
└── frontend/
```

## 로컬 실행

### 전체 통합 (docker-compose)

```bash
make docker        # 모든 이미지 빌드
make up            # localstack + kafka + 5개 서비스 기동
curl http://localhost:8081/    # frontend
curl http://localhost:8080/orders -X POST \
  -H 'Content-Type: application/json' -d '{"user_id":"u1","amount":100}'
make down          # 정리
```

### 단일 서비스 (go run)

```bash
cd order-service
go run .
```

## 테스트

```bash
make test          # 전체 서비스 + shared 테스트
```

## ECR 푸시

```bash
make ecr-push      # 또는 ../00-prerequisites/scripts/ecr-push-all.sh
```

## 메트릭 엔드포인트

모든 서비스는 `:9090/metrics` 와 `:9090/healthz` 노출.
