# Lab 01 — 사전 준비

## 학습 확인 포인트

- [ ] ECR 이미지가 5종 모두 푸시되어 있다
- [ ] order namespace 생성
- [ ] AWS LB Controller 가 동작 중

## 1. ECR 이미지 확인

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

for svc in order-service payment-service user-service notification-service frontend; do
  echo -n "→ $svc: "
  aws ecr describe-images --repository-name eks-study/$svc \
    --query 'imageDetails[?contains(imageTags, `latest`)]|[0].imagePushedAt' \
    --output text 2>/dev/null || echo "NOT FOUND"
done
```

`NOT FOUND` 면 푸시:
```bash
cd ../../
bash 00-prerequisites/scripts/ecr-push-all.sh
cd PART-2-EKS-Practice/09-msa-deploy/
```

## 2. ACCOUNT_ID 치환된 매니페스트 생성

매니페스트 안의 `ACCOUNT_ID` 자리표시자를 치환:

```bash
mkdir -p /tmp/msa
for f in manifests/order/*.yaml manifests/user/*.yaml manifests/payment/*.yaml manifests/notification/*.yaml manifests/frontend/*.yaml manifests/base/*.yaml; do
  sed "s/ACCOUNT_ID/$ACCOUNT_ID/g" "$f" > "/tmp/msa/$(basename $f)"
done

ls /tmp/msa/
```

## 3. Namespace 생성

```bash
kubectl apply -f /tmp/msa/namespace.yaml
kubectl get ns order
```

## 4. (옵션) ECR Pull 권한 점검

기본적으로 노드 IAM Role에 `AmazonEC2ContainerRegistryReadOnly` 정책이 있어야 ECR pull 가능.

```bash
NODE_ROLE=$(aws eks describe-nodegroup --cluster-name eks-study --nodegroup-name workers \
  --query 'nodegroup.nodeRole' --output text 2>/dev/null | awk -F/ '{print $NF}')
aws iam list-attached-role-policies --role-name $NODE_ROLE \
  --query 'AttachedPolicies[].PolicyName' --output text
```

기대: `AmazonEKSWorkerNodePolicy AmazonEKS_CNI_Policy AmazonEC2ContainerRegistryReadOnly`.

`AmazonEC2ContainerRegistryReadOnly` 누락이면 추가:
```bash
aws iam attach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

## 5. AWS LB Controller 동작 점검

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
kubectl get ingressclass alb
```

기대: 컨트롤러 Pod 2개 Running, IngressClass `alb` 존재.

## 학습 확인 질문

1. `AmazonEC2ContainerRegistryReadOnly` 가 노드 IAM Role 에 없으면 어떤 에러가 발생하는가?
2. ServiceMonitor 가 `monitoring` NS 에 있는데 `order` NS 의 Service 를 scrape 할 수 있는 이유는?
3. 매니페스트의 `ACCOUNT_ID` 자리표시자를 치환하는 방법으로 sed 외에 어떤 게 있을까?

다음: [lab-02-deploy-services.md](./lab-02-deploy-services.md)
