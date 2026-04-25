# 이론 — KEDA

## 1. HPA 의 한계

K8s 기본 **HorizontalPodAutoscaler** 가 잘 못하는 것:
- **Scale to zero** — `minReplicas: 1` 이 최소. 0 까지 못 줄임
- **이벤트 기반** — CPU/Memory 외에 큐 길이, Topic lag 같은 외부 지표 직접 사용 어려움
- 커스텀 메트릭은 metrics-server / prometheus-adapter 등 추가 컴포넌트 필요 + 복잡

## 2. KEDA 가 채우는 것

> Kubernetes Event-Driven Autoscaling

- **scale-to-zero** 가 기본 (`minReplicaCount: 0`)
- **50+ scalers**: AWS SQS, Kafka, RabbitMQ, Prometheus, Redis, MySQL, Cron, ...
- HPA 를 **자동 생성** — 내부적으로 HPA 의 external metrics 모드 사용
- 운영 부담 낮음 — KEDA Operator 1개 + ScaledObject CRD 만

## 3. 동작 원리

```
┌──────────────────────────────────────────────────────┐
│  KEDA Operator (Deployment)                          │
│   ├── controller — ScaledObject reconcile            │
│   └── metrics-server — HPA가 메트릭 가져갈 source     │
└──────────────────────────────────────────────────────┘
              │ (관찰)            │ (제공)
              ▼                    ▲
    [ScaledObject CRD]      [HPA (자동 생성)]
              │                    │
              │ scaleTarget         │ scaleTargetRef
              ▼                    ▼
        [Deployment "X"]
              │
              ▼
         [Pod 들]
```

KEDA Operator 가 외부 시스템(SQS, Prometheus 등) 메트릭을 폴링 → HPA 의 external metrics 로 노출 → HPA 가 그 값으로 Pod 수 결정.

**Scale-to-zero 메커니즘**: replicas == minReplicaCount(0) 일 때 KEDA 가 직접 Deployment.spec.replicas 를 0 으로. 이벤트 발생 시 다시 1+ 로 끌어올림.

## 4. ScaledObject CRD 기본 구조

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: my-scaler
spec:
  scaleTargetRef:
    name: my-app                          # Deployment 이름
  minReplicaCount: 0
  maxReplicaCount: 50
  pollingInterval: 30                     # 초당 외부 메트릭 폴링
  cooldownPeriod: 300                     # 5분 동안 트리거 0 이면 0 으로 축소
  triggers:
    - type: cpu
      metadata:
        type: Utilization
        value: "70"
    - type: prometheus
      metadata:
        serverAddress: http://prometheus.monitoring:9090
        metricName: http_requests_per_second
        threshold: "100"
        query: sum(rate(http_requests_total[1m]))
```

여러 trigger 동시 가능 — OR 로직 (어느 하나 임계 넘으면 scale up).

## 5. ScaledJob — Job 용

ScaledObject 는 Deployment / StatefulSet 대상. **단발성 작업** (큐 메시지 처리 등) 은 ScaledJob:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata:
  name: process-queue
spec:
  jobTargetRef:
    template:
      spec:
        containers:
          - name: worker
            image: my-worker:v1
        restartPolicy: Never
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: ...
        queueLength: "1"
```

→ 큐에 메시지 N 개 → Job N 개 자동 생성 → 처리 끝나면 사라짐.

## 6. TriggerAuthentication — 자격증명 분리

Trigger 가 외부에 인증 필요할 때 (AWS / DB 등):

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-sqs-auth
spec:
  podIdentity:
    provider: aws        # IRSA 사용
```

ScaledObject 에서 참조:
```yaml
triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: aws-sqs-auth
    metadata:
      queueURL: ...
      identityOwner: operator   # KEDA Operator 의 IAM Role 사용
```

본 lab 모듈 13 에서 본격적으로 다룸.

## 7. KEDA + Karpenter 시너지 (Module 14 의 핵심)

```
[SQS 메시지 폭증]
    ↓
[KEDA] Pod 0 → 50 으로 빠르게 스케일
    ↓
[K8s scheduler] 50 개 Pod 모두 스케줄 시도
    ↓
[일부 Pending] (기존 노드 부족)
    ↓
[Karpenter] Pending 보고 Spot 노드 즉시 추가
    ↓
[Pod 모두 Running]
    ↓
[메시지 처리 완료]
    ↓
[KEDA] Pod 50 → 0 (cooldown 후)
    ↓
[Karpenter] 빈 노드 회수
```

→ **인프라 비용은 처리량에 비례** (기본 시간엔 0).

다음: [lab-01-install.md](./lab-01-install.md)
