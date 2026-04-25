# Lab 01 — AWS Cost Explorer 활용

## 1. CLI 로 일별 EC2 비용

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-7d +%F),End=$(date -u +%F) \
  --granularity DAILY \
  --metrics UnblendedCost \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --query 'ResultsByTime[*].[TimePeriod.Start,Total.UnblendedCost.Amount]' \
  --output table
```

기대: 7일치 일별 EC2 비용. (학습 시작 후 며칠 안 됐으면 데이터 부족)

## 2. 서비스별 누적

```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-30d +%F),End=$(date -u +%F) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output table
```

## 3. 사용 유형별 (UsageType)

NAT GW / EBS / 데이터 전송을 분리해 보기:
```bash
aws ce get-cost-and-usage \
  --time-period Start=$(date -u -v-7d +%F),End=$(date -u +%F) \
  --granularity DAILY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=USAGE_TYPE \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute"]}}' \
  --query 'ResultsByTime[].Groups[?Metrics.UnblendedCost.Amount>`0.01`].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output text | sort | uniq -c | sort -rn | head
```

기대: BoxUsage:t3.medium / NatGateway-Hours / NatGateway-Bytes / DataTransfer-Out 등.

## 4. 콘솔 활용

CloudConsole → Cost Explorer → "Cost and usage reports".

**유용한 필터**:
- Service = EC2 + EKS + Load Balancer
- Tag = `Project: eks-study` (리소스 태깅 후)
- Dimension: Linked Account / Usage Type / Instance Type

**그룹화** 추천:
- Linked Account (멀티 계정)
- Service
- Usage Type
- Tag

## 5. 태그 기반 비용 분리

리소스에 `Project=<name>` 태그를 붙이면 Cost Explorer 에서 분리 추적 가능. Karpenter 의 EC2NodeClass 의 `tags` 필드 활용:

```yaml
spec:
  tags:
    Project: eks-study
    Team: platform
    Environment: learning
```

태그 활성화 (Cost Allocation Tags):
1. Console → Billing → Cost allocation tags
2. `Project`, `Team` 등 활성화
3. 24시간 후 Cost Explorer 에서 사용 가능

## 6. AWS Budgets 알람 (이미 00-prerequisites 에서 설정)

```bash
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) \
  --query 'Budgets[].[BudgetName,BudgetLimit.Amount,BudgetLimit.Unit]' --output table
```

추가 알람 — 일일 비용 (학습 환경 보호):
```bash
cat > /tmp/daily-budget.json <<EOF
{
  "BudgetName": "eks-study-daily",
  "BudgetLimit": {"Amount": "5", "Unit": "USD"},
  "TimeUnit": "DAILY",
  "BudgetType": "COST"
}
EOF
# 알람 추가는 setup-budget-alarm.sh 참고
```

## 학습 확인 질문

1. Cost Explorer 의 데이터는 얼마나 자주 갱신되나?
2. NAT GW 의 두 가지 비용 항목은?
3. 태그를 붙였는데 Cost Explorer 에서 안 보이는 이유는?

다음: [lab-02-rightsizing.md](./lab-02-rightsizing.md)
