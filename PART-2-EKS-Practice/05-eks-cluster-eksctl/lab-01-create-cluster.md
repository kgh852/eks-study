# Lab 01 — ClusterConfig로 EKS 클러스터 생성

## ⚠️ 비용 시작

이 lab부터 EKS Control Plane 비용($0.10/시간)이 발생합니다. Part 2 끝나면 반드시 클러스터 삭제.

## 학습 확인 포인트

- [ ] eksctl이 만드는 CloudFormation Stack을 봤다
- [ ] OIDC provider가 활성화됨을 확인했다
- [ ] kubectl로 노드/Pod에 접근 가능하다

## 1. (만약 Part 1 클러스터가 떠 있다면) 먼저 삭제

```bash
eksctl delete cluster --name eks-study --region ap-northeast-2 --wait
```

(이미 없다면 스킵)

## 2. ClusterConfig 검토

```bash
cat manifests/cluster.yaml
```

핵심 포인트:
- `iam.withOIDC: true` — IRSA 활성화
- `vpc.nat.gateway: Single` — NAT Gateway 1개로 비용 절감
- `managedNodeGroups.spot: true` — Spot 인스턴스
- `addons` — vpc-cni, coredns, kube-proxy, ebs-csi 사전 설치

## 3. 클러스터 생성

```bash
eksctl create cluster -f manifests/cluster.yaml
```

소요 시간: **15 ~ 20분**.

별도 터미널에서 진행 상황 모니터:
```bash
watch -n10 'aws cloudformation list-stacks \
  --query "StackSummaries[?starts_with(StackName,\`eksctl-eks-study\`)].[StackName,StackStatus]" \
  --output table'
```

```
StackName                              | StackStatus
eksctl-eks-study-cluster               | CREATE_IN_PROGRESS
eksctl-eks-study-addon-vpc-cni         | CREATE_IN_PROGRESS
eksctl-eks-study-nodegroup-workers     | CREATE_IN_PROGRESS
```

모두 `CREATE_COMPLETE` 가 되면 끝.

## 4. kubectl 접근 검증

```bash
kubectl config current-context
kubectl get nodes
kubectl get pods -A
```

기대:
```
NAME                                              STATUS   ROLES    AGE   VERSION
ip-10-20-x-x.ap-northeast-2.compute.internal     Ready    <none>   2m    v1.30.x
ip-10-20-y-y.ap-northeast-2.compute.internal     Ready    <none>   2m    v1.30.x

# 시스템 Pod (각 NS):
NAMESPACE     NAME
kube-system   aws-node-xxxxx          ← VPC CNI (DaemonSet)
kube-system   coredns-xxxxx
kube-system   ebs-csi-controller-xxx
kube-system   ebs-csi-node-xxxxx      ← DaemonSet
kube-system   kube-proxy-xxxxx        ← DaemonSet
```

## 5. OIDC provider 확인 (IRSA의 전제)

```bash
aws eks describe-cluster --name eks-study --region ap-northeast-2 \
  --query 'cluster.identity.oidc.issuer' --output text
```

기대 (URL 형식):
```
https://oidc.eks.ap-northeast-2.amazonaws.com/id/AAABBBCCC...
```

IAM Identity Provider 등록 확인:
```bash
ISSUER_HOSTPATH=$(aws eks describe-cluster --name eks-study --region ap-northeast-2 \
  --query 'cluster.identity.oidc.issuer' --output text | sed 's|https://||')

aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, '${ISSUER_HOSTPATH}')]"
```

기대: 1개 결과 (Arn).

## 6. CFN Stack 살펴보기

```bash
aws cloudformation describe-stack-resources \
  --stack-name eksctl-eks-study-cluster \
  --query 'StackResources[].[ResourceType,LogicalResourceId,PhysicalResourceId]' \
  --output table | head -30
```

생성된 자원 종류:
- `AWS::EC2::VPC`, `Subnet`, `RouteTable`, `NatGateway`, `InternetGateway`
- `AWS::EKS::Cluster`
- `AWS::IAM::Role` (Cluster Role + Service Role)

```bash
aws cloudformation describe-stack-resources \
  --stack-name eksctl-eks-study-nodegroup-workers \
  --query 'StackResources[].ResourceType' --output text
```

→ `AWS::EKS::Nodegroup` 등.

## 7. CloudWatch Logs 확인

ClusterConfig에서 `clusterLogging` 활성화했으므로:
```bash
aws logs describe-log-streams \
  --log-group-name /aws/eks/eks-study/cluster \
  --query 'logStreams[].logStreamName' --output text | head
```

```bash
aws logs tail /aws/eks/eks-study/cluster --follow --since 5m | head -20
```

→ kube-apiserver 등의 로그가 흐릅니다.

## 8. (선택) Access Entry 추가

다른 IAM 사용자가 이 클러스터를 쓰게 하려면:
```bash
ARN=arn:aws:iam::123456789012:user/colleague
aws eks create-access-entry --cluster-name eks-study --principal-arn $ARN
aws eks associate-access-policy --cluster-name eks-study \
  --principal-arn $ARN \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

## 학습 확인 질문

1. eksctl이 만드는 CFN Stack 중 클러스터 자체를 정의하는 stack의 이름은?
2. `iam.withOIDC: true` 가 만드는 AWS 자원은?
3. NAT Gateway를 `Single` 로 한 단점은?

다음: [lab-02-nodegroups.md](./lab-02-nodegroups.md)
