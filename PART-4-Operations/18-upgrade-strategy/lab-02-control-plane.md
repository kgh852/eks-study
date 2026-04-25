# Lab 02 — Control Plane 업그레이드

## ⚠️ 학습 환경에서는 1번만 시도 권장

업그레이드는 **다운그레이드 불가**. 학습용 클러스터를 1.30 → 1.31 로 한번 올리는 시나리오.

## 1. 사전 (반복) 점검

```bash
aws eks describe-cluster --name eks-study --query 'cluster.{version:version,status:status}'
# version: 1.30, status: ACTIVE 이어야 함
```

## 2. 업그레이드 시작

### 옵션 A — eksctl

```bash
eksctl upgrade cluster --name eks-study --version 1.31 --approve
```

### 옵션 B — AWS CLI

```bash
aws eks update-cluster-version --name eks-study --kubernetes-version 1.31
```

### 옵션 C — Terraform

`variables.tf` 에서 `cluster_version = "1.31"` 변경 후:
```bash
terraform plan
terraform apply
```

## 3. 진행 상황 모니터

```bash
watch -n10 'aws eks describe-cluster --name eks-study --query "cluster.{version:version,status:status}"'
```

기대:
```
status: UPDATING (~ 20분)
   ↓
status: ACTIVE
version: 1.31
```

## 4. CFN Stack 진행 (eksctl 사용 시)

```bash
aws cloudformation describe-stack-events \
  --stack-name eksctl-eks-study-cluster \
  --query 'StackEvents[0:10].[Timestamp,ResourceStatus,ResourceType]' \
  --output table
```

## 5. 워크로드 영향 확인

업그레이드 동안 (그리고 후에) 워크로드 정상 여부:
```bash
# Pod 들 모두 Running
kubectl get pods -A | grep -vE 'Running|Completed' | head

# API 호출 가능
kubectl get nodes
kubectl version --short
```

기대: API 일시적 1~2분 지연 가능하지만 워크로드 자체엔 영향 없음.

## 6. CoreDNS / kube-proxy 자동 업그레이드?

EKS Addon 으로 설치한 것은 **자동 X**. 다음 lab 에서 명시적 업데이트.

```bash
eksctl get addon --cluster eks-study
```

addon version 컬럼이 옛 버전인지 확인.

## 7. 업그레이드 후 새 기능 / 변경

EKS 릴리즈 노트 확인:
- https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- 1.31 의 변경: in-place pod resize, new APIs 등

## 8. 학습 확인

- 업그레이드는 한 번에 한 마이너 버전만 가능한가?
- 업그레이드 중 `kubectl` 명령이 일시적으로 실패할 수 있는데, 그 이유는?
- 만약 1.30 → 1.32 한번에 가려면 어떻게?

다음: [lab-03-nodes.md](./lab-03-nodes.md)
