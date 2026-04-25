# 이론 — EKS 아키텍처

## 1. 책임 분담: AWS vs 사용자

```
┌─ AWS 책임 ─────────────────────────────┐
│  Control Plane                          │
│  ├─ kube-apiserver                      │
│  ├─ etcd                                │
│  ├─ scheduler                           │
│  ├─ controller-manager                  │
│  └─ (멀티 AZ 자동 복제, 패치, 백업)      │
└─────────────────────────────────────────┘
              │ (HTTPS API endpoint)
              ▼
┌─ 사용자 책임 ───────────────────────────┐
│  Data Plane                             │
│  ├─ Worker Nodes (EC2 또는 Fargate)      │
│  ├─ kubelet, kube-proxy, container rt   │
│  ├─ 워크로드 (Pod, Deployment, ...)       │
│  ├─ Networking (VPC, SG, IAM)           │
│  └─ Add-on (CNI, CSI, Ingress, ...)      │
└─────────────────────────────────────────┘
```

- **Control Plane**: AWS가 운영. 비용 시간당 약 $0.10. 직접 SSH 접근 불가, 로그는 CloudWatch로.
- **Data Plane**: 사용자가 운영. 노드를 직접 관리하거나 (Self-managed) AWS가 더 도와주는 모드 (Managed Node Group, Fargate) 선택.

## 2. 노드 옵션 3가지

### 2.1 Managed Node Group

- AWS가 EC2 Auto Scaling Group을 관리
- 업데이트, 종료, 교체 자동화
- 학습/실무 기본 선택

### 2.2 Self-managed

- 직접 ASG 관리 → 더 큰 자유도 (커스텀 AMI, 특수 인스턴스 타입)
- 운영 부담 큼

### 2.3 Fargate

- 노드 개념 자체 없음. Pod 단위 서버리스
- VPC, 시간당 비용 모델
- Cold start, 일부 기능 제한 (DaemonSet 불가, GPU 불가)
- Karpenter 학습 목적이면 부적합

→ **본 커리큘럼은 Managed Node Group + Spot 사용.**

## 3. eksctl 의 역할

eksctl 명령 1번이 내부적으로 만드는 것:
- **CloudFormation Stack 여러 개**:
  - `eksctl-<cluster>-cluster` — VPC, IAM Role(Cluster), EKS Cluster 자체
  - `eksctl-<cluster>-nodegroup-<name>` — 노드 그룹 ASG, IAM Role
- **Kubeconfig 자동 갱신** (`~/.kube/config`)
- **OIDC provider** (옵션) — IRSA용
- **addon** 설치 (옵션)

CFN 콘솔에서 직접 보기:
```bash
aws cloudformation list-stacks \
  --query 'StackSummaries[?starts_with(StackName,`eksctl-eks-study`)].[StackName,StackStatus]' \
  --output table
```

## 4. ClusterConfig YAML

명령어 옵션 대신 YAML로 클러스터 정의 — 재현성, 코드화.

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: eks-study
  region: ap-northeast-2
  version: "1.30"

iam:
  withOIDC: true        # IRSA 위해 필수

managedNodeGroups:
  - name: workers
    instanceType: t3.medium
    spot: true
    desiredCapacity: 2
    minSize: 0
    maxSize: 10
    volumeType: gp3
    iam:
      withAddonPolicies:
        ebs: true
        cloudWatch: true

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver
```

## 5. EKS 버전 정책

- 신규 마이너 버전이 약 분기마다 출시
- 각 버전은 **약 14개월 지원** (Standard) → 만료되기 전 업그레이드
- 학습용은 항상 최신 또는 N-1 권장 (1.30 또는 1.31)

```bash
eksctl utils describe-addon-versions --kubernetes-version 1.30
```

## 6. 인증 (Auth) — IAM ↔ K8s RBAC

K8s 자체에는 IAM 사용자/역할 개념이 없습니다. EKS는 다음 두 메커니즘 중 하나:

### 6.1 aws-auth ConfigMap (Legacy)

`kube-system/aws-auth` ConfigMap에 IAM ARN을 K8s user/group 으로 매핑.
```yaml
mapUsers: |
  - userarn: arn:aws:iam::xxx:user/devops
    username: devops
    groups:
      - system:masters
```

### 6.2 EKS Access Entries (신규, 2024+)

```bash
aws eks create-access-entry \
  --cluster-name eks-study \
  --principal-arn arn:aws:iam::xxx:user/devops \
  --type STANDARD

aws eks associate-access-policy \
  --cluster-name eks-study \
  --principal-arn arn:aws:iam::xxx:user/devops \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

→ ConfigMap 편집 안 해도 됨, IAM 정책처럼 관리.

본 커리큘럼은 Access Entries 권장.

다음: [lab-01-create-cluster.md](./lab-01-create-cluster.md)
