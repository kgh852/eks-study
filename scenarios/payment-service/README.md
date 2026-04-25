# payment-service

AWS SQS 메시지를 컨슘하여 결제 처리를 시뮬레이션하는 워커 서비스. **Part 3 KEDA 학습의 핵심**: SQS 큐 길이 기반 ScaledObject 시연.

## 동작

1. `SQS_QUEUE_URL` 큐를 long-poll
2. 메시지 수신 시 JSON 파싱 → 로깅 (실제 결제 호출은 시뮬레이션 처리)
3. 정상 처리 후 메시지 삭제 (실패 시 visibility timeout 후 재시도)

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `SQS_QUEUE_URL` | (필수) | SQS 큐 URL |
| `AWS_REGION` | (AWS SDK 기본값) | AWS 리전 |

## 로컬 실행 (LocalStack 사용 시)

```bash
docker run -d --rm -p 4566:4566 -e SERVICES=sqs localstack/localstack
aws --endpoint-url=http://localhost:4566 sqs create-queue --queue-name payments
AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_REGION=us-east-1 \
  SQS_QUEUE_URL=http://localhost:4566/000000000000/payments \
  go run .
```

## 테스트

```bash
go test ./...
```

## Part 3 KEDA 트리거 (예고)

```yaml
triggers:
  - type: aws-sqs-queue
    metadata:
      queueURL: ...
      queueLength: "5"  # 메시지 5개당 파드 1개
```
