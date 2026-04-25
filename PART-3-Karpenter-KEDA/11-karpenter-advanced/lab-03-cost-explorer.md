# Lab 03 — Cost Explorer 로 비용 비교

## 학습 확인 포인트

- [ ] Karpenter 가 만든 노드의 실제 시간당 비용을 계산해본다
- [ ] Spot vs On-Demand 비용 차이 비교
- [ ] AWS Cost Explorer 에서 EC2 비용 추이 확인

## 1. 현재 Karpenter 노드 비용 산정

```bash
# 가격 정보 가져오기 (간단히 — Spot 가격은 AZ 별)
INSTANCES=$(kubectl get nodes -L node.kubernetes.io/instance-type \
  -o jsonpath='{range .items[?(@.metadata.labels.managed-by=="karpenter")]}{.status.allocatable.cpu}{"\t"}{.metadata.labels.node\.kubernetes\.io/instance-type}{"\t"}{.metadata.labels.topology\.kubernetes\.io/zone}{"\n"}{end}')

echo "$INSTANCES" | while read cpu type zone; do
  if [[ -n "$type" ]]; then
    PRICE=$(aws ec2 describe-spot-price-history \
      --instance-types $type \
      --product-descriptions "Linux/UNIX" \
      --availability-zone $zone \
      --max-results 1 \
      --query 'SpotPriceHistory[0].SpotPrice' --output text 2>/dev/null)
    echo "$type ($zone): \$$PRICE/hour (Spot)"
  fi
done
```

기대 (예시):
```
c5a.large (ap-northeast-2a): $0.0260/hour (Spot)
m6a.large (ap-northeast-2b): $0.0312/hour (Spot)
```

(On-Demand 대비 약 60~70% 저렴)

## 2. On-Demand vs Spot 비교

```bash
for type in c5.large c5a.large m5.large m6a.large t3.large; do
  OD=$(aws ec2 describe-spot-price-history \
    --instance-types $type \
    --product-descriptions "Linux/UNIX" \
    --max-results 1 \
    --query 'SpotPriceHistory[0].SpotPrice' --output text 2>/dev/null)
  echo "$type: Spot \$$OD/hr"
done
```

ap-northeast-2 의 일반적 시간당 가격 (참고):
| Type | On-Demand | Spot | 절감 |
|------|-----------|------|------|
| t3.medium | $0.052 | ~$0.016 | 69% |
| c5.large | $0.10 | ~$0.030 | 70% |
| m5.large | $0.118 | ~$0.038 | 68% |
| m6a.large | $0.107 | ~$0.032 | 70% |

## 3. Cost Explorer API

지난 24시간 EC2 비용:
```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-1d +%F),End=$(date -u +%F) \
  --granularity HOURLY \
  --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --query 'ResultsByTime[*].[TimePeriod.Start,Total.UnblendedCost.Amount]' \
  --output text | tail -10
```

> 학습 시작 후 24시간 이내라면 데이터가 부족할 수 있음. AWS Console 의 Cost Explorer UI 가 시각화에 좋음.

## 4. EC2 인스턴스 사용 시간 분석

Karpenter 가 만들고 종료한 인스턴스들의 lifetime:
```bash
aws ec2 describe-instances \
  --filters "Name=tag:karpenter.sh/nodepool,Values=spot,ondemand" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,InstanceLifecycle,LaunchTime,State.Name,StateTransitionReason]' \
  --output table
```

종료된 인스턴스의 LaunchTime ~ 종료 시각 차이가 그 인스턴스의 비용 청구 시간.

## 5. CloudWatch Container Insights 와 결합

(Module 08 에서 설치한 Container Insights 가 떠 있다면)

CloudWatch → Container Insights → eks-study → Performance.
- Node CPU/Memory utilization
- Pod 별 사용량 vs Request 비율 → over-provision 인 워크로드 식별

## 6. 비용 절감 체크리스트

| 항목 | 효과 |
|------|------|
| Spot 우선 + 다양화 | 60~70% 절감 |
| Consolidation 활성 | underutilized 노드 자동 회수 |
| 인스턴스 타입 제한 (큰 거 배제) | over-provisioning 방지 |
| 적절한 requests / limits | Karpenter 가 정확히 sizing |
| 야간/주말 자동 스케일 다운 | KEDA cron trigger (Module 12) |

## 학습 확인 질문

1. Karpenter 가 Spot 가격을 실시간으로 어떻게 알까?
2. Spot 70% 절감의 트레이드오프는?
3. 노드 1대의 Spot 가격이 갑자기 비싸지면 Karpenter 가 어떻게 대응?

다음: [quiz.md](./quiz.md)
