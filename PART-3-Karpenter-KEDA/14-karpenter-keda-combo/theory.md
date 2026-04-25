# 이론 — Karpenter + KEDA 시나리오 설계

## 1. 흐름

```
시각  T=0
[큐 메시지 = 0]
[Pod = 0 (payment-service, scale-to-zero)]
[Karpenter 노드 = 0]
[비용 = 0/시간]

시각  T=10s   [SQS 에 메시지 1만 건 주입]
[큐 = 10000]

시각  T=30s   [KEDA 폴링]
KEDA: queueLength=10000, threshold=5 → desired = 2000 (cap 30)
KEDA: Deployment.replicas 0 → 30
30 Pod 가 Pending (기존 노드 부족)

시각  T=45s   [Karpenter 가 Pending 보고 NodeClaim 생성]
Karpenter: m5a.xlarge (4 vCPU, 16Gi) × 2대 → "충분히 들어가는 인스턴스 타입"
NodeClaim 생성 → EC2 launch

시각  T=90s   [노드 join]
Pod 들이 새 노드에 스케줄, Running

시각  T=180s  [메시지 처리 시작]
큐 길이 감소: 10000 → 8000 → 5000 → ...

시각  T=600s  [큐 = 0]
KEDA cooldown 시작 (90초)

시각  T=690s  [KEDA: replicas 30 → 0]
Pod 모두 종료

시각  T=720s  [Karpenter: 빈 노드 회수]
NodeClaim 삭제, EC2 종료

시각  T=750s
[Pod = 0, Node = 0, 비용 = 0/시간]
```

## 2. 비용 계산

**가정**:
- m5a.xlarge spot 가격: 약 $0.05/시간
- 노드 2대 × 12분 = 0.4 시간
- 비용: 2 × 0.05 × 0.4 = **$0.04**

**같은 처리를 항상 켜둔 노드 2대 (m5a.xlarge spot) 로 한다면**:
- 24시간 × 0.05 × 2 = **$2.40/일** = **$72/월**

→ 트래픽 패턴이 burst 면 KEDA + Karpenter 가 95% 비용 절감.

## 3. KEDA 의 메시지/Pod 비율 계산

- queueLength=5 → 5 메시지 당 Pod 1개 권장
- 큐=10000, threshold=5 → 2000 desired (이론)
- maxReplicaCount=30 → 30 으로 제한
- 30 Pod × 처리속도 (예: 5 msg/s/Pod) = 150 msg/s
- 10000 / 150 ≈ 67초

→ maxReplicaCount 를 어떻게 잡느냐가 처리 시간을 결정. 30 으로 한 이유:
- 노드 자원 제한 (학습용)
- payment-service 의 in-memory 처리 속도 가정

## 4. Karpenter 의 노드 선택 로직

30 Pod (각 50m CPU, 64Mi 요청) → 총 1.5 CPU + 2 Gi 메모리.

가능한 노드 옵션:
- m5.xlarge (4 vCPU): 1대로 충분 (시스템 Pod + payment 30개)
- m5.large (2 vCPU): 2대 필요
- t3.medium (2 vCPU): 3대 필요 (작은 인스턴스)

Karpenter 는 **가장 작은 비용** 으로 만족하는 조합 선택. Spot 가격 / 가용성에 따라 동적.

## 5. 관찰 포인트

이 시나리오에서 보고 싶은 것:
1. **KEDA 의 응답 속도** — 메시지 도착 → Pod 시작 까지 (목표 < 60초)
2. **Karpenter 의 응답 속도** — Pending → 노드 Ready 까지 (목표 < 90초)
3. **End-to-end 메시지 처리 시간** — 전체 1만건 처리 시간
4. **비용** — 처리에 든 정확한 EC2 시간

## 6. 메트릭 시각화

Module 08 의 Grafana 사용:
- "Kubernetes / Compute Resources / Namespace (Pods)" 대시보드
- 또는 직접 PromQL:
  - Pod 수: `count(kube_pod_info{namespace="order",created_by_name=~"payment-service"})`
  - Node 수: `count(kube_node_info)`
  - 큐 길이: KEDA 가 노출하는 external metric (또는 CloudWatch metric `ApproximateNumberOfMessages`)

다음: [lab-01-setup.md](./lab-01-setup.md)
