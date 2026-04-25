# Lab 01 — Karpenter 설치

## 학습 확인 포인트

- [ ] Karpenter 공식 CFN 템플릿이 만드는 것을 봤다
- [ ] IRSA 로 Karpenter Controller 가 EC2 API 호출 가능
- [ ] Helm 으로 Karpenter Pod 가 떠 있다

## 1. 환경 변수

```bash
export CLUSTER_NAME=eks-study
export AWS_REGION=ap-northeast-2
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export KARPENTER_VERSION="1.0.6"     # 본 lab 시점 stable
```

## 2. 공식 CFN 템플릿으로 IAM/SQS 셋업

```bash
TEMP=$(mktemp)
curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > $TEMP

aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file $TEMP \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}" \
  --region ${AWS_REGION}
```

이 CFN Stack 이 만드는 것:
- `KarpenterNodeRole-eks-study` — 노드용 IAM Role
- `KarpenterControllerRole-eks-study` — Controller IRSA용
- `KarpenterInterruptionQueue-eks-study` — Spot Interruption SQS
- EventBridge Rules (EC2 Spot, Health, Rebalance → SQS)

## 3. Karpenter NodeRole 을 클러스터 aws-auth 에 추가 (또는 Access Entries)

노드가 join 하려면 클러스터의 RBAC 등록 필요.

**Access Entries 사용** (EKS 1.30+ 권장):
```bash
aws eks create-access-entry \
  --cluster-name ${CLUSTER_NAME} \
  --principal-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --type EC2_LINUX \
  --region ${AWS_REGION}
```

또는 **aws-auth ConfigMap** 사용:
```bash
eksctl create iamidentitymapping --cluster ${CLUSTER_NAME} \
  --region ${AWS_REGION} \
  --arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --username "system:node:{{EC2PrivateDNSName}}" \
  --group system:bootstrappers \
  --group system:nodes
```

## 4. 서브넷 / 보안그룹 태깅

Karpenter 가 어느 서브넷 / SG 를 쓸지 알도록 태그:

```bash
# 서브넷 (private)
SUBNETS=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
  --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
aws ec2 create-tags --resources $SUBNETS \
  --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}"

# 클러스터 보안그룹
CLUSTER_SG=$(aws eks describe-cluster --name ${CLUSTER_NAME} --region ${AWS_REGION} \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 create-tags --resources $CLUSTER_SG \
  --tags "Key=karpenter.sh/discovery,Value=${CLUSTER_NAME}"
```

## 5. Helm 설치

```bash
helm registry logout public.ecr.aws 2>/dev/null

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace karpenter --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=Karpenter-${CLUSTER_NAME}" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:role/KarpenterControllerRole-${CLUSTER_NAME}" \
  --set "controller.resources.requests.cpu=100m" \
  --set "controller.resources.requests.memory=512Mi" \
  --set "controller.resources.limits.memory=1Gi" \
  --wait
```

## 6. 검증

```bash
kubectl get pods -n karpenter
kubectl get crd | grep karpenter
```

기대:
```
NAME                          READY   STATUS    RESTARTS   AGE
karpenter-xxx-aaa             1/1     Running   0          2m
karpenter-xxx-bbb             1/1     Running   0          2m

ec2nodeclasses.karpenter.k8s.aws
nodeclaims.karpenter.sh
nodepools.karpenter.sh
```

## 7. Controller 로그

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=20
```

기대 (대략):
```
INFO  starting controller manager
INFO  webhook server ...
INFO  starting reconciler  for: nodepool.karpenter.sh
INFO  spot interruption queue ready  queue=Karpenter-eks-study
```

## 학습 확인 질문

1. CFN 템플릿이 만드는 IAM Role 두 개의 차이는 (Controller vs Node)?
2. Karpenter 가 만든 노드가 클러스터에 join 하려면 어떤 권한이 필요한가?
3. `karpenter.sh/discovery` 태그를 안 붙이면 어떻게 되는가?

다음: [lab-02-first-nodepool.md](./lab-02-first-nodepool.md)
