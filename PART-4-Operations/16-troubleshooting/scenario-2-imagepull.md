# 시나리오 2 — ImagePullBackOff

## 1. 재현

오타가 있는 이미지로 Pod 만들기:
```bash
kubectl run badimg --image=public.ecr.aws/eks-distro/no-such-image:v999
sleep 30
```

## 2. 증상

```bash
kubectl get pod badimg
```

```
NAME     READY   STATUS             RESTARTS   AGE
badimg   0/1     ErrImagePull       0          15s
# 또는 ImagePullBackOff
```

## 3. 진단

```bash
kubectl describe pod badimg | tail -20
```

기대 (Events):
```
Failed to pull image "...no-such-image:v999": ... manifest unknown
```

## 4. 원인 분류

| 메시지 | 원인 |
|--------|------|
| `manifest unknown` / `not found` | 이미지 이름 / 태그 오타 |
| `unauthorized` / `denied` | 사설 레지스트리 인증 누락 |
| `no basic auth credentials` | ECR — 노드 IAM Role 의 ECR 권한 누락 |
| `dial tcp ... timeout` | 네트워크 (NAT GW 없음, VPC endpoint 미설정) |

## 5. 해결 — 각 원인별

### 5.1 오타 / 잘못된 태그
```bash
# 사용 가능한 태그 확인
aws ecr describe-images --repository-name eks-study/order-service \
  --query 'imageDetails[].imageTags' | jq
```

### 5.2 ECR 권한
```bash
NODE_ROLE=$(aws eks describe-nodegroup --cluster-name eks-study --nodegroup-name workers \
  --query 'nodegroup.nodeRole' --output text | awk -F/ '{print $NF}')
aws iam attach-role-policy --role-name $NODE_ROLE \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

### 5.3 사설 레지스트리 (Docker Hub 인증 등)
```bash
kubectl create secret docker-registry myregistry \
  --docker-server=https://index.docker.io/v1/ \
  --docker-username=USERNAME \
  --docker-password=PASSWORD

# Pod spec 에 imagePullSecrets 추가
```

## 6. 정리

```bash
kubectl delete pod badimg
```

## 학습 확인

- ECR 노드 IAM Role 의 정책 이름은?
- Pod 가 `ErrImagePull` 상태 후 `ImagePullBackOff` 로 가는 경계는?
- 같은 이미지를 같은 노드에 여러 번 pull 하면 캐시 동작은?
