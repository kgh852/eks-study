# Lab 01 — Terraform 으로 클러스터 만들기

## 1. terraform 디렉토리 진입

```bash
cd terraform/
ls
```

기대:
```
versions.tf  variables.tf  locals.tf  outputs.tf
vpc.tf  eks.tf  irsa.tf
karpenter.tf  keda.tf  alb-controller.tf
```

## 2. terraform init

```bash
terraform init
```

→ `.terraform/` 안에 provider 와 모듈 다운로드. ~2분.

## 3. plan

```bash
terraform plan -out tf.plan
```

기대: 100+ 자원 생성 예정 (VPC, Subnet, IGW, NAT GW, EKS Cluster, NodeGroup, IAM Role, ...).

## 4. 자원 일부만 먼저 만들기 (학습 권장)

VPC + EKS 만 먼저 (Helm 은 나중에 — 의존성 명확화):
```bash
terraform apply -target=module.vpc -target=module.eks
```

소요: ~15분 (EKS 클러스터 자체 시간).

## 5. kubeconfig 등록

```bash
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

기대: 노드 2대 Ready.

## 6. 나머지 (Helm + Karpenter NodePool)

```bash
terraform apply
```

소요: 추가 5~7분.

## 7. 확인

```bash
kubectl get nodepool,ec2nodeclass
kubectl get pods -n karpenter
kubectl get pods -n keda
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## 8. eksctl 로 만든 클러스터와 비교

| 항목 | eksctl | Terraform |
|------|--------|-----------|
| 클러스터 생성 시간 | 15~20분 | 동일 |
| Karpenter / KEDA 추가 명령 | 별도 helm install | 같은 apply 안에 |
| state 추적 | CFN | tfstate |
| 다음 변경 시 | clusterconfig 수정 + create-nodegroup 등 | terraform apply |
| 삭제 | eksctl delete (CFN 기반) | terraform destroy |

다음: [lab-02-addons.md](./lab-02-addons.md)
