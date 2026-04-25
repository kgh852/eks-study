# Lab 01 — EBS CSI Driver IRSA 검증

## 학습 확인 포인트

- [ ] EBS CSI Controller Pod 의 SA 에 IAM Role 어노테이션이 있음을 확인
- [ ] IAM Role Trust Policy 의 `sub` 조건을 직접 봤다
- [ ] Pod 안에서 STS 토큰을 직접 확인

## 1. EBS CSI 의 ServiceAccount 확인

```bash
kubectl get sa -n kube-system ebs-csi-controller-sa -o yaml | yq '.metadata.annotations'
```

기대:
```yaml
eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/AmazonEKS_EBS_CSI_DriverRole
```

→ ClusterConfig 의 `wellKnownPolicies.ebsCSIController: true` 가 자동 셋업.

## 2. IAM Role 의 Trust Policy 살펴보기

```bash
ROLE_ARN=$(kubectl get sa -n kube-system ebs-csi-controller-sa \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
ROLE_NAME=$(echo $ROLE_ARN | awk -F/ '{print $NF}')
echo "Role: $ROLE_NAME"

aws iam get-role --role-name $ROLE_NAME --query 'Role.AssumeRolePolicyDocument' --output json
```

기대:
```json
{
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks..."},
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.ap-northeast-2.amazonaws.com/id/XXX:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      }
    }
  }]
}
```

## 3. Pod 안에서 토큰 확인

```bash
POD=$(kubectl get pods -n kube-system -l app=ebs-csi-controller -o name | head -1)
kubectl exec -n kube-system $POD -c ebs-plugin -- env | grep AWS
```

기대:
```
AWS_DEFAULT_REGION=ap-northeast-2
AWS_REGION=ap-northeast-2
AWS_ROLE_ARN=arn:aws:iam::xxx:role/AmazonEKS_EBS_CSI_DriverRole
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

```bash
kubectl exec -n kube-system $POD -c ebs-plugin -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token | head -c 100
echo
```

JWT 형식. 디코딩하려면:
```bash
kubectl exec -n kube-system $POD -c ebs-plugin -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token \
  | awk -F. '{print $2}' | base64 -d 2>/dev/null
```

기대 (필드들):
```json
{
  "aud": ["sts.amazonaws.com"],
  "exp": ...,
  "iss": "https://oidc.eks.ap-northeast-2.amazonaws.com/id/XXX",
  "kubernetes.io": {
    "namespace": "kube-system",
    "serviceaccount": {"name": "ebs-csi-controller-sa", ...}
  },
  "sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
}
```

→ IAM Role의 Trust 의 `:sub` 조건과 정확히 일치.

## 4. 실제 EBS API 호출 검증

```bash
# 임의로 PVC 만들어보기
cat > /tmp/test-pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-irsa-pvc
spec:
  storageClassName: gp2
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-irsa
spec:
  containers:
    - name: app
      image: alpine:3.19
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: test-irsa-pvc
EOF

kubectl apply -f /tmp/test-pvc.yaml
kubectl get pvc test-irsa-pvc --watch    # Bound 까지 기다림 (몇 초)
```

EBS CSI Controller 의 로그에서 IRSA 로 EBS API 호출하는 것 확인:
```bash
kubectl logs -n kube-system -l app=ebs-csi-controller -c ebs-plugin --tail=20 \
  | grep -i 'createvolume\|volumeID'
```

## 5. 정리

```bash
kubectl delete -f /tmp/test-pvc.yaml
```

## 학습 확인 질문

1. EBS CSI 의 SA 어노테이션을 다른 IAM Role 의 ARN 으로 바꾸면 어떻게 될까?
2. JWT 토큰의 `:sub` 가 다른 SA 였다면 STS는 어떤 응답을 주는가?
3. Pod이 다중 컨테이너일 때 IRSA 토큰은 어느 컨테이너에 마운트되나?

다음: [lab-02-app-irsa-s3.md](./lab-02-app-irsa-s3.md)
