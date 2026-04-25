# 이론 — IRSA & Pod Identity

## 1. 문제: K8s ServiceAccount 가 AWS IAM 을 어떻게 쓰지?

### 옛날 방식: 노드 IAM Role 공유
- 노드 EC2 인스턴스 프로파일에 IAM Role 을 부여
- 그 노드의 모든 Pod 이 같은 IAM 권한을 갖게 됨
- **문제**: 한 Pod 만 S3 권한이 필요한데 모든 Pod에 부여 → 최소 권한 위반

### 해결책: IRSA — Pod 별로 IAM Role

> ServiceAccount 단위로 IAM Role 부여 → Pod이 자기 SA 에 매핑된 IAM Role 권한만 사용

## 2. IRSA 동작 원리

```
┌─ 1. AWS는 EKS 클러스터의 OIDC issuer URL을 IAM에 등록 (Identity Provider)
│
├─ 2. IAM Role의 Trust Policy: "이 OIDC issuer 가 발급한 토큰 + 특정 SA 면 신뢰"
│
├─ 3. K8s SA의 annotation: eks.amazonaws.com/role-arn=arn:aws:iam:...
│
├─ 4. Pod 시작 시 kubelet이 Projected Token 을 Pod에 자동 마운트
│     (이 토큰은 OIDC issuer 가 서명한 JWT)
│
├─ 5. Pod 의 AWS SDK 가 토큰 감지 → STS AssumeRoleWithWebIdentity 호출
│     - Role ARN: SA annotation 에서
│     - WebIdentityToken: 마운트된 토큰
│
└─ 6. STS 가 토큰의 OIDC 서명을 검증 → IAM Role 의 임시 자격증명 반환
      Pod 의 AWS SDK 가 이 자격증명으로 AWS API 호출
```

## 3. SA Annotation 형식

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-app-role
```

## 4. IAM Role Trust Policy 형식

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::123456789012:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/XXXX"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "oidc.eks.ap-northeast-2.amazonaws.com/id/XXXX:sub": "system:serviceaccount:default:my-app",
        "oidc.eks.ap-northeast-2.amazonaws.com/id/XXXX:aud": "sts.amazonaws.com"
      }
    }
  }]
}
```

핵심: `:sub` 조건이 `system:serviceaccount:<ns>:<sa>` 정확히 일치해야 함.

## 5. Pod에 자동 마운트되는 토큰

```bash
kubectl exec -it <pod> -- ls /var/run/secrets/eks.amazonaws.com/serviceaccount/
# → token (JWT)
```

```bash
kubectl exec -it <pod> -- env | grep AWS
# AWS_ROLE_ARN=arn:aws:iam:...
# AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

→ AWS SDK가 이 두 환경변수를 자동으로 감지해 AssumeRoleWithWebIdentity.

## 6. eksctl 의 편의 명령

수동으로 위를 다 해도 되지만 eksctl이 한 번에:
```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=default \
  --name=my-app \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve
```

수행하는 일:
1. CloudFormation Stack 만들어 IAM Role 생성 (Trust 정책 포함)
2. K8s SA 생성 + annotation 자동 설정

## 7. Pod Identity (2024+ 신규)

IRSA 의 한계:
- IAM Role 의 Trust 정책에 OIDC issuer 와 SA name 을 정확히 박아야 함
- 클러스터 마이그레이션 / SA 이동 시 Trust 정책 수정 필요

**Pod Identity** 는 다음을 해결:
```bash
aws eks create-pod-identity-association \
  --cluster-name eks-study \
  --namespace default \
  --service-account my-app \
  --role-arn arn:aws:iam::xxx:role/my-app-role
```

- IAM Role의 Trust 는 EKS Pod Identity Service 만 신뢰 (간단한 정책)
- 클러스터 ID 와 SA 매핑은 EKS Pod Identity Agent (DaemonSet) 가 담당
- Role 재사용 더 쉬움

전제: `eks-pod-identity-agent` addon 설치 필요.

| | IRSA | Pod Identity |
|---|---|---|
| 출시 | 2019 | 2023말 / 2024 |
| Trust Policy | OIDC issuer + sub 박아야 함 | 단순 (`pods.eks.amazonaws.com`) |
| Role 재사용 | 어려움 (issuer 마다 정책 따로) | 쉬움 (여러 클러스터/SA에 연결) |
| 토큰 발급 | kubelet (Projected Token) | Pod Identity Agent |
| 의존성 | OIDC provider | `eks-pod-identity-agent` addon |
| 권장 | 기존 자산 / 멀티-클러스터 호환 | 신규 클러스터 |

본 커리큘럼: IRSA 기본, Pod Identity 도 한 lab 에서 시연.

다음: [lab-01-ebs-csi-irsa.md](./lab-01-ebs-csi-irsa.md)
