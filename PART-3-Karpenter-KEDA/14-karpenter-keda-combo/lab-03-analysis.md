# Lab 03 — 결과 분석 + 비용

## 1. EC2 사용 시간 정확히 측정

```bash
# Karpenter 가 만든 인스턴스 목록 (이번 시연으로 종료된 것 포함)
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=spot,ondemand" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,InstanceLifecycle,LaunchTime,StateTransitionReason]' \
  --output table
```

`StateTransitionReason` 에 종료 시각 포함 (terminated 라면).

## 2. 인스턴스별 비용 계산

```bash
# 가장 최근 시연의 인스턴스들만 집계
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=spot" \
  "Name=launch-time,Values=$(date -u -v-1H +%FT%TZ)*" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,LaunchTime]' \
  --output table
```

각 인스턴스에 대해:
- LaunchTime ~ 종료 시각의 차이 = 사용 시간
- 그 시점의 Spot 가격 (대략 $0.04 ~ $0.06/시간)

수동 계산 예:
- 노드 2대 × 12분 = 24분 (= 0.4 시간)
- 평균 Spot $0.045/h × 0.4 = **$0.018**

## 3. CloudWatch / Prometheus 그래프

### Prometheus
```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
```

쿼리:
```
# Pod 수
count(kube_pod_info{namespace="order",created_by_name=~"payment-service.*"})

# 노드 수 (Karpenter 만)
count(kube_node_labels{label_managed_by="karpenter"})
```

지난 1시간 그래프 → spike + tail 모양 보임.

### Grafana
- "Kubernetes / Compute Resources / Namespace (Pods)"
  - Namespace=order
  - Pod 별 CPU/Mem 변화
- 또는 "Kubernetes / Cluster" 의 노드 수 그래프

## 4. SQS 처리량 분석

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name NumberOfMessagesReceived \
  --dimensions Name=QueueName,Value=eks-study-payments \
  --start-time $(date -u -v-1H +%FT%TZ) \
  --end-time $(date -u +%FT%TZ) \
  --period 60 \
  --statistics Sum \
  --query 'Datapoints[*].[Timestamp,Sum]' --output text | sort
```

분당 처리량 → 처음 0 → spike → 다시 0.

## 5. 비교: KEDA + Karpenter 없이 같은 처리

가상 시나리오: 항상 30 Pod 가 떠있다면?
- 30 Pod × 100m CPU = 3 CPU 필요
- m5a.xlarge (4 vCPU) 1대 항상 켜둠
- 24h × 30day × $0.05/h = **$36/월**

vs 실제 (KEDA + Karpenter):
- 12분 × $0.04 = **$0.04**
- 하루 1번 burst 가정 시: $0.04 × 30 = **$1.2/월**

**95%+ 비용 절감**.

## 6. 시연으로 확인한 핵심

| 메트릭 | 값 (예상) |
|--------|----------|
| KEDA 첫 응답 (Pod 0→1) | ~30초 |
| Pod 수 0 → 30 도달 | ~60초 |
| Karpenter 노드 Ready | ~90초 |
| 1만건 처리 완료 | ~7~10분 |
| Pod 0 으로 복귀 (cooldown 후) | ~12분 |
| 노드 0 으로 복귀 | ~13분 |
| 총 EC2 비용 | < $0.05 |

## 학습 확인 질문

1. KEDA + Karpenter 가 항상 비용 절감인가? 어떤 트래픽 패턴에서 효과 큰가?
2. cold start 가 견딜 수 없는 워크로드는 어떻게 대응?
3. maxReplicaCount 를 더 늘리면 처리 빨라질까? 한계는?

다음: [quiz.md](./quiz.md)
