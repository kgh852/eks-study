# Lab 03 — terraform destroy 로 정리

## 1. 사전 정리 — K8s 자원 먼저

LoadBalancer Service 는 직접 삭제. 안 그러면 ALB 가 남아 VPC 삭제 차단:
```bash
kubectl delete ingress --all -A
kubectl delete svc --field-selector spec.type=LoadBalancer -A
sleep 60
```

## 2. terraform destroy

```bash
cd terraform/
terraform destroy
```

→ "Yes" 입력. 약 15분.

## 3. 잔존 리소스 확인

```bash
echo "=== EKS Clusters ==="
aws eks list-clusters --region ap-northeast-2 | jq

echo "=== EC2 Instances (Karpenter / Node Group) ==="
aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=eks-study-tf" \
  Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId'

echo "=== ALBs ==="
aws elbv2 describe-load-balancers --query 'LoadBalancers[?starts_with(LoadBalancerName,`k8s-`)].LoadBalancerName'

echo "=== EBS unattached ==="
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[].VolumeId'

echo "=== VPC ==="
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=eks-study" --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0]]'
```

기대: 모두 비어있음. 무엇이 남으면 직접 삭제.

## 4. tfstate 백업

```bash
mv terraform.tfstate terraform.tfstate.backup-$(date +%Y%m%d)
ls -la *.tfstate*
```

state 는 학습 기록으로 보관 권장.

## Part 3 종료

축하합니다 🎉 — Part 3 완료.

남은 것: Part 4 운영/트러블슈팅.

- 만약 Part 4 진행 전 잠시 쉬려면, 클러스터를 삭제했으니 비용 0.
- Part 4 시작 시 클러스터 다시 생성:

```bash
# Option A: eksctl
eksctl create cluster -f ../../PART-2-EKS-Practice/05-eks-cluster-eksctl/manifests/cluster.yaml

# Option B: terraform
cd terraform/ && terraform apply
```

다음: [quiz.md](./quiz.md)
