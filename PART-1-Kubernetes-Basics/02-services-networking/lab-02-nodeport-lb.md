# Lab 02 — NodePort, LoadBalancer

## ⚠️ 비용 주의

이 lab의 LoadBalancer는 **AWS NLB를 실제로 만듭니다**. 끝나면 반드시 cleanup.
- NLB 시간당: 약 0.0225 USD
- 1시간 실습: 약 0.05 USD

## 학습 확인 포인트

- [ ] NodePort로 노드 IP에서 직접 접근해봤다
- [ ] LoadBalancer 가 자동으로 NLB를 만드는 걸 봤다
- [ ] LB DNS로 외부에서 접근해봤다

## 1. NodePort 배포 (web Deployment 가 lab-01에서 떠 있다고 가정)

```bash
kubectl apply -f manifests/nodeport.yaml
kubectl get svc web-nodeport
```

기대:
```
NAME           TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
web-nodeport   NodePort   10.100.234.56    <none>        80:30080/TCP   10s
```

`PORT(S)` 가 `80:30080/TCP` — 클러스터 내부 80, 노드 외부 30080.

## 2. NodePort로 접근 시도

EKS 노드의 SG는 기본적으로 **30080 포트가 막혀있을 수 있습니다**. 임시로 열기:

```bash
# 노드 SG ID 찾기 (한 노드 기준)
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=${NODE_NAME}" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
SG_ID=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[].Instances[].SecurityGroups[].GroupId' --output text | awk '{print $1}')

echo "Node SG: $SG_ID"

# 30080 포트 임시 오픈 (학습용. 실무 금지)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 30080 --cidr 0.0.0.0/0

# 노드 퍼블릭 IP
NODE_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[].Instances[].PublicIpAddress' --output text)
echo "Node IP: $NODE_IP"

curl http://$NODE_IP:30080/
```

> **운영에서는** NodePort를 인터넷에 직접 노출하지 않습니다. LoadBalancer/Ingress 사용.

테스트 끝나면 SG 룰 회수:
```bash
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 30080 --cidr 0.0.0.0/0
```

## 3. LoadBalancer 배포

```bash
kubectl apply -f manifests/loadbalancer.yaml
kubectl get svc web-lb --watch     # EXTERNAL-IP 가 채워질 때까지 대기 (1~3분)
```

기대 (시간 지나면):
```
NAME      TYPE           CLUSTER-IP       EXTERNAL-IP                                                        PORT(S)        AGE
web-lb    LoadBalancer   10.100.55.123    a1b2c3d4e5...elb.ap-northeast-2.amazonaws.com   80:31234/TCP   2m
```

## 4. LB DNS로 외부 접근

```bash
LB_DNS=$(kubectl get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "LB: $LB_DNS"

curl http://$LB_DNS/
```

기대: nginx 페이지 또는 `web-xxx` (lab-01에서 hostname 주입했다면).

## 5. AWS 콘솔에서 NLB 확인

```bash
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(DNSName, `'$LB_DNS'`)].[LoadBalancerName,Type,Scheme,State.Code]' \
  --output table
```

또는 콘솔: EC2 → Load Balancers → 방금 만든 NLB 선택 → Listener / Target group 확인.

**Target group의 health check** 가 통과해야 LB가 트래픽을 보냅니다. 처음에는 `Initial` 또는 `Unhealthy` 일 수 있고 30초~1분 후 `Healthy` 로 전환.

## 6. `kubectl describe` 로 어노테이션 확인

```bash
kubectl describe svc web-lb | grep -A20 'Annotations\|Selector\|Type\|LoadBalancer Ingress'
```

매니페스트에서 준 어노테이션이 그대로 있고, 그 결과 NLB가 만들어졌습니다.

## 7. 정리 (반드시!)

```bash
kubectl delete -f manifests/loadbalancer.yaml
kubectl delete -f manifests/nodeport.yaml
```

LB가 실제로 사라졌는지 확인:
```bash
sleep 30
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text
```

기대: 우리가 만든 LB는 보이지 않음.

## 학습 확인 질문

1. LoadBalancer 타입 Service는 NodePort 와 ClusterIP를 함께 만드나?
2. 인터넷 노출 시 NodePort 직접 사용을 권하지 않는 이유 두 가지?
3. `kubectl delete svc web-lb` 만으로 NLB가 정말로 삭제되는 메커니즘은? (어떤 컴포넌트가 그 일을 함?)

다음: [lab-03-dns.md](./lab-03-dns.md)
