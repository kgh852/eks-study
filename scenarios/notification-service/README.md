# notification-service

Kafka topic을 컨슘하여 알림 발송을 시뮬레이션하는 워커 서비스. **Part 3 KEDA Kafka 트리거 시연용**.

## 동작

1. `KAFKA_BROKERS`의 `KAFKA_TOPIC`을 `KAFKA_GROUP` 컨슈머 그룹으로 구독
2. 메시지 수신 시 로깅 (실제 알림 발송은 시뮬레이션)
3. 정상 처리 후 오프셋 커밋

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `KAFKA_BROKERS` | `localhost:9092` | 콤마로 구분된 브로커 주소 |
| `KAFKA_TOPIC` | `notifications` | 구독 토픽 |
| `KAFKA_GROUP` | `notification-service` | 컨슈머 그룹 ID |

## 로컬 실행 (docker-compose 사용 권장)

```bash
# scenarios/ 루트에서
docker compose up -d kafka
KAFKA_BROKERS=localhost:9092 go run .
```

## 테스트

```bash
go test ./...
```

## Part 3 KEDA 트리거 (예고)

```yaml
triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka:9092
      consumerGroup: notification-service
      topic: notifications
      lagThreshold: "10"
```
