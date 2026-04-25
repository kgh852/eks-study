# Lab 02 — AWS Load Balancer Controller 설치

## 학습 확인 포인트

- [ ] IAM Policy → IAM Role → ServiceAccount (IRSA) 흐름을 직접 만들어봤다
- [ ] Helm 으로 컨트롤러 설치 + values 설정
- [ ] 컨트롤러 Pod이 Ready 됨

## 1. IAM Policy 다운로드 + 생성

```bash
curl -o /tmp/iam_policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file:///tmp/iam_policy.json \
  --query 'Policy.Arn' --output text
```

기대: `arn:aws:iam::123456789012:policy/AWSLoadBalancerControllerIAMPolicy`

이미 있으면 에러 (그대로 진행 OK).

## 2. IRSA로 SA + IAM Role 한 번에

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve \
  --region=ap-northeast-2
```

이 명령이 한 번에:
- IAM Role 생성 (Trust 정책: 클러스터 OIDC를 신뢰)
- K8s ServiceAccount 생성 (`kube-system/aws-load-balancer-controller`)
- SA 의 annotation `eks.amazonaws.com/role-arn` 자동 설정

검증:
```bash
kubectl get sa aws-load-balancer-controller -n kube-system -o yaml | yq '.metadata.annotations'
```

## 3. Helm 으로 컨트롤러 설치

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=eks-study \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=ap-northeast-2 \
  --set vpcId=$(aws eks describe-cluster --name eks-study --query 'cluster.resourcesVpcConfig.vpcId' --output text)
```

## 4. 검증

```bash
kubectl wait --for=condition=available --timeout=120s \
  deploy/aws-load-balancer-controller -n kube-system

kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

기대:
```
NAME                                            READY   STATUS    RESTARTS   AGE
aws-load-balancer-controller-xxxxx-aaaaa        1/1     Running   0          30s
aws-load-balancer-controller-xxxxx-bbbbb        1/1     Running   0          30s
```

로그 확인:
```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller --tail=20
```

기대: `successfully acquired lease`, `Starting Controller` 등의 로그.

## 5. CRD 확인

```bash
kubectl get crd | grep elbv2
```

기대:
```
ingressclassparams.elbv2.k8s.aws
targetgroupbindings.elbv2.k8s.aws
```

## 6. IngressClass 생성

```bash
cat > /tmp/ingressclass.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
  annotations:
    ingressclass.kubernetes.io/is-default-class: "true"
spec:
  controller: ingress.k8s.aws/alb
EOF
kubectl apply -f /tmp/ingressclass.yaml

kubectl get ingressclass
```

이제 Ingress 리소스에 `ingressClassName: alb` 또는 기본값으로 ALB 자동 생성.

## 학습 확인 질문

1. IRSA 가 ServiceAccount 의 annotation 으로 `eks.amazonaws.com/role-arn` 만 설정했는데, 어떻게 IAM 권한이 작동하는가?
2. `serviceAccount.create=false` 옵션을 준 이유는?
3. 컨트롤러 Pod이 2개 떠 있는 이유는? (HA?)

다음: [lab-03-alb-ingress.md](./lab-03-alb-ingress.md)
