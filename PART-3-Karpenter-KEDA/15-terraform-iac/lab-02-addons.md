# Lab 02 — Addons 동작 검증

## 1. Karpenter NodePool / EC2NodeClass 가 만들어졌는지

```bash
kubectl get nodepool,ec2nodeclass
kubectl describe ec2nodeclass default
```

기대: READY=True.

`kubernetes_manifest` 리소스가 Helm 후 `time_sleep` 30초 후에 적용. 처음 apply 시 가끔 Karpenter Pod 가 아직 안 떠서 실패할 수 있음 → 두 번째 apply 가 정상.

## 2. KEDA + IRSA 검증

```bash
kubectl get sa -n keda keda-operator -o yaml | yq '.metadata.annotations'
```

기대: `eks.amazonaws.com/role-arn` 가 채워져 있음.

```bash
kubectl logs -n keda -l app=keda-operator --tail=20
```

## 3. AWS LB Controller 검증

```bash
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml | yq '.metadata.annotations'
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

## 4. 간단한 워크로드 배포 (eks-study 클러스터에서 했던 것 재현)

```bash
# Module 09 의 매니페스트를 새 클러스터에 적용
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
mkdir -p /tmp/tf-msa
for f in ../../PART-2-EKS-Practice/09-msa-deploy/manifests/order/*.yaml \
         ../../PART-2-EKS-Practice/09-msa-deploy/manifests/user/*.yaml \
         ../../PART-2-EKS-Practice/09-msa-deploy/manifests/payment/*.yaml \
         ../../PART-2-EKS-Practice/09-msa-deploy/manifests/notification/*.yaml \
         ../../PART-2-EKS-Practice/09-msa-deploy/manifests/frontend/*.yaml \
         ../../PART-2-EKS-Practice/09-msa-deploy/manifests/base/namespace.yaml \
         ../../PART-2-EKS-Practice/09-msa-deploy/manifests/base/ingress.yaml; do
  sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" "$f" > "/tmp/tf-msa/$(basename $f)"
done

kubectl apply -f /tmp/tf-msa/
kubectl get all -n order
```

## 5. (옵션) MSA 와 KEDA SQS 결합 시연

위 Module 14 의 시나리오를 새 클러스터에서 다시 한 번:
```bash
# SQS 큐 생성
aws sqs create-queue --queue-name eks-study-payments-tf

# (이후 모듈 13/14 의 절차와 동일)
```

## 6. Terraform 변경 후 재적용

예: NodePool 의 limits 변경:
```hcl
# karpenter.tf 수정
limits = { cpu = "200" }    # 100 → 200
```

```bash
terraform plan
terraform apply
```

→ 변경된 리소스만 update. (idempotent)

## 다음: [lab-03-destroy.md](./lab-03-destroy.md)
