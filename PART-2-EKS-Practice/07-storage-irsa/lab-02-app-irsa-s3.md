# Lab 02 — 앱에 IRSA 적용 (S3 접근)

목표: AWS CLI 가 들어있는 Pod 에 IRSA 로 S3 ReadOnly 권한 부여 → S3 버킷 목록 조회.

## 학습 확인 포인트

- [ ] `eksctl create iamserviceaccount` 가 무엇을 만드는지 직접 확인
- [ ] IRSA 없이 호출 → 실패, IRSA 있으면 성공 → 비교
- [ ] IAM Policy 변경이 즉시 반영됨 (Pod 재시작 불필요)

## 1. 실습용 S3 버킷 만들기

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="eks-study-irsa-${ACCOUNT_ID}"

aws s3 mb s3://${BUCKET_NAME} --region ap-northeast-2
echo "test content" | aws s3 cp - s3://${BUCKET_NAME}/test.txt
aws s3 ls s3://${BUCKET_NAME}/
```

## 2. IRSA 없이 시도 — 실패 케이스

```bash
cat > /tmp/no-irsa-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: s3-no-irsa
spec:
  containers:
    - name: aws
      image: amazon/aws-cli:2.15.0
      command: ["sleep", "3600"]
EOF

kubectl apply -f /tmp/no-irsa-pod.yaml
kubectl wait --for=condition=ready pod s3-no-irsa --timeout=60s

kubectl exec s3-no-irsa -- aws s3 ls s3://${BUCKET_NAME}/
```

기대:
```
Unable to locate credentials. You can configure credentials by running "aws configure".
```

(또는 노드 IAM Role 권한이 있으면 성공할 수도 있음 — 그 경우 의도 불명확. 다음 단계로)

```bash
kubectl delete -f /tmp/no-irsa-pod.yaml
```

## 3. IRSA SA 생성 (eksctl)

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=default \
  --name=s3-reader \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve \
  --region=ap-northeast-2

kubectl get sa s3-reader -o yaml | yq '.metadata.annotations'
```

기대: `eks.amazonaws.com/role-arn` 이 채워져 있음.

## 4. IRSA 로 Pod 실행

```bash
cat > /tmp/irsa-pod.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: s3-with-irsa
spec:
  serviceAccountName: s3-reader
  containers:
    - name: aws
      image: amazon/aws-cli:2.15.0
      command: ["sleep", "3600"]
EOF

kubectl apply -f /tmp/irsa-pod.yaml
kubectl wait --for=condition=ready pod s3-with-irsa --timeout=60s

# 환경변수 자동 주입 확인
kubectl exec s3-with-irsa -- env | grep AWS
```

기대: `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` 자동으로 보임.

## 5. 실제 호출

```bash
# 정체 확인 — STS 가 임시 자격증명을 줬는지
kubectl exec s3-with-irsa -- aws sts get-caller-identity

# S3 호출
kubectl exec s3-with-irsa -- aws s3 ls s3://${BUCKET_NAME}/
kubectl exec s3-with-irsa -- aws s3 cp s3://${BUCKET_NAME}/test.txt -
```

기대: 성공.

## 6. 권한 한계 시연 — 쓰기 시도

```bash
echo "from-pod" | kubectl exec -i s3-with-irsa -- aws s3 cp - s3://${BUCKET_NAME}/from-pod.txt
```

기대:
```
upload failed: ... AccessDenied
```

ReadOnly 정책이라 PUT 거부.

## 7. 권한 추가 — Trust 와 Policy 변경 즉시 반영

기존 Role 에 정책 추가:
```bash
ROLE_ARN=$(kubectl get sa s3-reader -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
ROLE_NAME=$(echo $ROLE_ARN | awk -F/ '{print $NF}')

aws iam attach-role-policy --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

# Pod 재시작 없이 다시 시도
sleep 10   # 자격증명 캐싱 만료 대기 (보통 5분이지만 새 호출은 새 토큰)
kubectl exec s3-with-irsa -- aws s3 cp /etc/hostname s3://${BUCKET_NAME}/from-pod.txt
kubectl exec s3-with-irsa -- aws s3 ls s3://${BUCKET_NAME}/
```

기대: 성공 (PUT 권한 부여됨).

> **주의**: 자격증명은 STS 토큰 캐시 (~1시간). 즉시 변화는 컨테이너의 SDK 가 자격증명을 새로 가져올 때 반영. 새 Pod 면 즉시.

## 8. 정리

```bash
kubectl delete -f /tmp/irsa-pod.yaml
eksctl delete iamserviceaccount --cluster=eks-study --namespace=default --name=s3-reader \
  --region=ap-northeast-2 --wait

# S3 버킷 삭제
aws s3 rm s3://${BUCKET_NAME} --recursive
aws s3 rb s3://${BUCKET_NAME}
```

## 학습 확인 질문

1. `aws sts get-caller-identity` 의 응답에서 `Arn` 가 어떤 형태였나? (assumed-role/...)
2. 같은 IAM Role 을 두 개의 SA 에 매핑하고 싶으면 Trust Policy 의 sub 조건은 어떻게 작성?
3. Pod 의 토큰이 만료되면 어떻게 갱신되나?

다음: [lab-03-pod-identity.md](./lab-03-pod-identity.md)
