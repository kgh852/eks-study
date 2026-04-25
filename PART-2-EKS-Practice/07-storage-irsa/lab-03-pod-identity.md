# Lab 03 — Pod Identity (IRSA의 진화형)

## 학습 확인 포인트

- [ ] Pod Identity Agent addon 설치
- [ ] Trust Policy가 IRSA 보다 단순함을 봤다
- [ ] 같은 IAM Role 을 여러 클러스터/SA 에 재사용 가능

## 1. EKS Pod Identity Agent addon 설치

```bash
eksctl create addon --cluster eks-study \
  --name eks-pod-identity-agent \
  --region ap-northeast-2

kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent
```

기대: 노드별 1개 Pod (DaemonSet).

## 2. Pod Identity 용 IAM Role 생성

Trust Policy 가 IRSA 보다 훨씬 단순:

```bash
cat > /tmp/pod-identity-trust.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "pods.eks.amazonaws.com"},
    "Action": ["sts:AssumeRole", "sts:TagSession"]
  }]
}
EOF

aws iam create-role \
  --role-name PodIdentityS3Reader \
  --assume-role-policy-document file:///tmp/pod-identity-trust.json

aws iam attach-role-policy \
  --role-name PodIdentityS3Reader \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

> **차이점**: OIDC issuer URL 도, sub condition 도 없음. `pods.eks.amazonaws.com` Service 만 신뢰.

## 3. ServiceAccount 만들고 Pod Identity Association 생성

```bash
kubectl create sa pod-identity-sa
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws eks create-pod-identity-association \
  --cluster-name eks-study \
  --namespace default \
  --service-account pod-identity-sa \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/PodIdentityS3Reader \
  --region ap-northeast-2
```

## 4. Pod 실행

```bash
cat > /tmp/pi-pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pi-test
spec:
  serviceAccountName: pod-identity-sa
  containers:
    - name: aws
      image: amazon/aws-cli:2.15.0
      command: ["sleep", "3600"]
EOF

kubectl apply -f /tmp/pi-pod.yaml
kubectl wait --for=condition=ready pod pi-test --timeout=60s

kubectl exec pi-test -- aws sts get-caller-identity
kubectl exec pi-test -- aws s3 ls
```

기대: `Arn` 이 `assumed-role/PodIdentityS3Reader/<session>`.

## 5. SA annotation 비교

```bash
kubectl get sa pod-identity-sa -o yaml | yq '.metadata.annotations'
# IRSA의 eks.amazonaws.com/role-arn 어노테이션이 없음!
```

→ Pod Identity 는 SA 어노테이션이 아니라 **EKS Pod Identity Association** 이라는 별도 리소스로 매핑.

## 6. 같은 Role 을 다른 SA 에도 연결

```bash
kubectl create sa another-sa -n kube-system

aws eks create-pod-identity-association \
  --cluster-name eks-study \
  --namespace kube-system \
  --service-account another-sa \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/PodIdentityS3Reader

aws eks list-pod-identity-associations --cluster-name eks-study \
  --query 'associations[].[namespace,serviceAccount,roleArn]' --output table
```

→ 같은 IAM Role 이 두 SA 에 매핑됨. **IRSA 였다면** Trust Policy 의 sub 조건을 두 개로 늘려야 했을 것.

## 7. 정리

```bash
kubectl delete -f /tmp/pi-pod.yaml
kubectl delete sa pod-identity-sa
kubectl delete sa another-sa -n kube-system

# Association 삭제
for assoc in $(aws eks list-pod-identity-associations --cluster-name eks-study \
  --query 'associations[].associationId' --output text); do
  aws eks delete-pod-identity-association --cluster-name eks-study --association-id $assoc
done

aws iam detach-role-policy --role-name PodIdentityS3Reader \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam delete-role --role-name PodIdentityS3Reader
```

## IRSA vs Pod Identity 정리

| | IRSA | Pod Identity |
|---|---|---|
| Trust 정책 | OIDC issuer + SA sub 박아야 함 | `pods.eks.amazonaws.com` 만 |
| Role 재사용 | 각 SA 마다 sub 추가 | Association 만 추가 |
| 새 클러스터 | OIDC issuer 다르므로 Trust 정책 추가 | 같은 Role 재사용 |
| 의존성 | OIDC provider | `eks-pod-identity-agent` addon |
| 출시 | 2019 | 2023말 |
| 생태계 | 거의 모든 도구 지원 | 일부 SDK 버전 필요 |

> 신규 프로젝트라면 **Pod Identity** 권장. 기존 IRSA 도 잘 동작하므로 굳이 마이그레이션할 필요는 없음.

## 학습 확인 질문

1. Pod Identity 의 IAM Role 재사용성이 IRSA 보다 좋은 이유는?
2. Pod Identity 가 동작하려면 클러스터에 어떤 컴포넌트가 떠 있어야 하나?
3. 같은 클러스터에서 IRSA 와 Pod Identity 를 동시 사용 가능한가?

다음: [quiz.md](./quiz.md)
