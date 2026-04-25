# Lab 03 — ALB Ingress 시연

## ⚠️ 비용

ALB가 만들어지면 시간당 약 0.0225 USD. 학습 끝나면 즉시 삭제.

## 학습 확인 포인트

- [ ] Ingress 리소스 적용만으로 ALB가 자동 생성됨을 봤다
- [ ] ALB Target Group에 Pod IP가 직접 등록됨을 확인했다 (IP target type)
- [ ] ALB DNS로 외부에서 접근 가능

## 1. echo 앱 + Ingress 적용

```bash
kubectl apply -f manifests/echo-ingress.yaml
kubectl get deploy,svc,ingress
```

## 2. Ingress 상태 확인

```bash
kubectl get ingress echo --watch
```

처음에는 `ADDRESS` 가 비어있다가 약 1~2분 후 ALB DNS로 채워짐:
```
NAME   CLASS   HOSTS   ADDRESS                                                            PORTS
echo   alb     *       k8s-default-echo-xxxxxxxxxx.ap-northeast-2.elb.amazonaws.com       80
```

## 3. AWS 콘솔에서 ALB 확인

```bash
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Type==`application`].[LoadBalancerName,DNSName,State.Code]' \
  --output table
```

```bash
ALB_NAME=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Type==`application`]|[0].LoadBalancerName' \
  --output text)
echo "ALB: $ALB_NAME"

# Target Group 확인
TG_ARN=$(aws elbv2 describe-target-groups \
  --query "TargetGroups[?contains(LoadBalancerArns[0], '$ALB_NAME')]|[0].TargetGroupArn" \
  --output text)
echo "TG: $TG_ARN"

# Targets (Pod IP가 직접 등록되어 있어야 함)
aws elbv2 describe-target-health --target-group-arn $TG_ARN \
  --query 'TargetHealthDescriptions[].[Target.Id,Target.Port,TargetHealth.State]' \
  --output table
```

기대:
```
+----------------+------+---------+
| 10.20.x.y      | 80   | healthy |
| 10.20.x.z      | 80   | healthy |
+----------------+------+---------+
```

→ `Target.Id` 가 Pod IP! Instance 모드라면 노드 IP였을 텐데, IP 모드라 직접.

## 4. 외부에서 호출

```bash
ALB_DNS=$(kubectl get ingress echo -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB DNS: $ALB_DNS"

curl -s http://$ALB_DNS/ | jq .host       # echo-server는 요청 정보를 JSON 으로 반환
curl -s http://$ALB_DNS/foo/bar | jq '.path,.headers'
```

## 5. path 라우팅 시연

매니페스트 수정:
```bash
cat > /tmp/echo-paths.yaml <<'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: study
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: echoserver
                port: { number: 80 }
          - path: /
            pathType: Prefix
            backend:
              service:
                name: echoserver
                port: { number: 80 }
EOF

kubectl apply -f /tmp/echo-paths.yaml

# 재호출
curl -s http://$ALB_DNS/api/orders | jq .path
curl -s http://$ALB_DNS/health | jq .path
```

## 6. ALB 삭제 확인

```bash
kubectl delete -f manifests/echo-ingress.yaml
sleep 30

aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?Type==`application`].LoadBalancerName' --output text
```

기대: 빈 결과 (또는 우리가 만든 게 없음).

## 학습 확인 질문

1. `target-type: ip` vs `target-type: instance` 의 차이를 한 줄로?
2. `alb.ingress.kubernetes.io/group.name` 어노테이션의 효과는?
3. Ingress 리소스를 삭제했는데 ALB가 안 사라지면 무엇을 점검?

다음: [quiz.md](./quiz.md)
