# 이론 — Event-Driven Scaling

## 1. SQS Scaler 동작

```
[KEDA Operator] ─ 폴링 ──→ [SQS Queue]
       │                      ApproximateNumberOfMessages
       ▼
   threshold 와 비교 → desired replicas 계산 → HPA external metric
```

**핵심 메트릭**: `ApproximateNumberOfMessages` (SQS 의 GetQueueAttributes API).
- threshold=5, queue=50 → 50/5 = 10 replicas 권장
- maxReplicaCount 가 상한.

**ScaledObject 예시**:
```yaml
triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: keda-trigger-auth-aws
    metadata:
      queueURL: https://sqs.ap-northeast-2.amazonaws.com/123456789012/payments
      queueLength: "5"
      awsRegion: ap-northeast-2
      identityOwner: operator    # Operator 의 IRSA 사용
```

## 2. Kafka Scaler 동작

```
[KEDA Operator] ─ 폴링 ──→ [Kafka Broker]
       │                  consumer-group lag (offset 차이)
       ▼
   lagThreshold 비교 → replicas 계산
```

**핵심 메트릭**: 컨슈머 그룹의 **lag** (가장 최근 produced offset - 컨슈머의 committed offset).
- lagThreshold=10, lag=200 → 20 replicas 권장
- 단, **partition 수 ≤ replicas 한계** (partition 수보다 많은 컨슈머는 idle)

**ScaledObject**:
```yaml
triggers:
  - type: kafka
    metadata:
      bootstrapServers: kafka.kafka:9092
      consumerGroup: notification-service
      topic: notifications
      lagThreshold: "10"
      offsetResetPolicy: latest
```

## 3. IRSA + KEDA TriggerAuthentication

KEDA 가 SQS 호출하려면 IAM 권한 필요. 두 가지 방식:

### 3.1 Operator 의 IAM Role 사용 (`identityOwner: operator`)

KEDA Operator Pod 의 SA 에 IRSA → 모든 SQS scaler 가 그 권한 사용.
간단하지만 한 IAM Role 이 모든 큐 접근 권한 필요.

### 3.2 워크로드의 IAM Role 사용 (`identityOwner: pod`)

워크로드 Pod 의 SA + KEDA TriggerAuthentication 으로 매핑. 큐별 권한 분리 가능.

본 lab 은 1번 (operator) 방식.

## 4. KEDA Operator 에 IRSA 부여 (SQS 권한)

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=keda \
  --name=keda-operator \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess \
  --override-existing-serviceaccounts \
  --approve
```

→ KEDA Operator Pod 가 SQS GetQueueAttributes 호출 가능.

## 5. payment-service 도 SQS 권한 필요

KEDA 가 큐 길이 보고 Pod 늘려도, **Pod 자체** 가 메시지를 ReceiveMessage / DeleteMessage 하려면 자기 IRSA 가 또 필요. 별도 SA + IRSA.

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=order \
  --name=payment-service \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonSQSFullAccess \
  --override-existing-serviceaccounts \
  --approve
```

(Module 09 에 미리 SA 가 있고 placeholder 어노테이션이 있었음 — 이제 실제 IRSA 적용)

## 6. Kafka in-cluster — Strimzi Operator

EKS 안에 Kafka 를 쉽게 띄우려면 **Strimzi**:
```bash
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  -n kafka --create-namespace --set watchAnyNamespace=true

# Kafka 클러스터 생성 (KRaft 모드, 단일 노드 학습용)
kubectl apply -n kafka -f - <<'EOF'
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: dual-role
  labels:
    strimzi.io/cluster: my-cluster
spec:
  replicas: 1
  roles: [controller, broker]
  storage:
    type: persistent-claim
    size: 10Gi
    deleteClaim: true
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: my-cluster
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 3.7.0
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      offsets.topic.replication.factor: 1
      transaction.state.log.replication.factor: 1
      transaction.state.log.min.isr: 1
      default.replication.factor: 1
  entityOperator:
    topicOperator: {}
    userOperator: {}
EOF
```

→ in-cluster `my-cluster-kafka-bootstrap.kafka:9092` 로 접근 가능.

## 7. 운영 환경 — MSK 권장

학습은 in-cluster Kafka, 운영은 **AWS MSK** 권장:
- 클러스터 외부 (VPC 같음)
- AWS 가 운영 (패치, 백업)
- KEDA Kafka scaler 가 동일하게 사용 (bootstrapServers 만 변경)

다음: [lab-01-sqs.md](./lab-01-sqs.md)
