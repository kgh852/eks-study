# Lab 02 — 5개 서비스 배포

## 학습 확인 포인트

- [ ] 5개 서비스 모두 Ready
- [ ] ALB 자동 생성, frontend / order-service 에 라우팅
- [ ] ServiceMonitor 가 메트릭 scrape 시작

## 1. 적용 (lab-01에서 만든 /tmp/msa/ 사용)

```bash
kubectl apply -f /tmp/msa/namespace.yaml
kubectl apply -f /tmp/msa/deployment.yaml -n order || true   # 무시. 다음 줄들로
kubectl apply -f /tmp/msa/   # 모두

kubectl get pods -n order --watch
```

또는 한 줄:
```bash
kubectl apply -f /tmp/msa/
```

기대 (몇 분 후):
```
NAME                                 READY   STATUS    RESTARTS   AGE
order-service-xxx-aaa                1/1     Running   0          1m
order-service-xxx-bbb                1/1     Running   0          1m
user-service-xxx-aaa                 1/1     Running   0          1m
user-service-xxx-bbb                 1/1     Running   0          1m
payment-service-xxx-aaa              1/1     Running   0          1m
notification-service-xxx-aaa         0/1     CrashLoopBackOff       ← 정상 (Kafka 없음)
frontend-xxx-aaa                     1/1     Running   0          1m
frontend-xxx-bbb                     1/1     Running   0          1m
```

> notification-service 는 Kafka 가 없어서 실패하는 게 **정상**. Part 3 모듈 13에서 Kafka 를 띄우면 정상 동작.

## 2. Service 확인

```bash
kubectl get svc -n order
```

기대:
```
NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
frontend               ClusterIP   10.100.x.y      <none>        80/TCP
order-service          ClusterIP   10.100.x.y      <none>        80/TCP, 9090/TCP
user-service           ClusterIP   10.100.x.y      <none>        50051/TCP, 9090/TCP
payment-service        ClusterIP   None            <none>        9090/TCP
notification-service   ClusterIP   None            <none>        9090/TCP
```

## 3. Ingress 확인

```bash
kubectl get ingress -n order msa --watch
```

ADDRESS가 채워질 때까지 1~2분 대기:
```
NAME   CLASS   HOSTS   ADDRESS                                                     PORTS
msa    alb     *       k8s-eksstudy-xxxxxx.ap-northeast-2.elb.amazonaws.com        80
```

## 4. 외부 호출 테스트

```bash
ALB_DNS=$(kubectl get ingress -n order msa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: http://$ALB_DNS"

# Frontend
curl -s http://$ALB_DNS/ | grep "EKS Study Demo"

# Order API
curl -s -X POST http://$ALB_DNS/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"u1","amount":1500}' | jq

# 같은 ID 로 GET
ID=$(curl -s -X POST http://$ALB_DNS/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"u1","amount":2000}' | jq -r .id)
curl -s http://$ALB_DNS/api/orders/$ID | jq
```

## 5. 클러스터 내부 통신 (gRPC) 확인

```bash
kubectl run -it --rm grpc-test --image=fullstorydev/grpcurl:v1.9.0-buster \
  -n order \
  --command -- /bin/grpcurl -plaintext \
  -d '{"name":"finn","email":"f@x.io"}' \
  user-service:50051 user.v1.UserService/CreateUser
```

기대: `id`, `name`, `email` 이 들어있는 JSON.

## 6. ServiceMonitor 검증 (Part 8 monitoring 이 떠 있다고 가정)

```bash
kubectl apply -f /tmp/msa/servicemonitor.yaml

# Prometheus 에서 target 확인
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &

# 브라우저 http://localhost:9090/targets 에서 "order-msa" 검색
# 또는 CLI
sleep 30
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="order-msa")'
```

## 7. 메트릭 쿼리

```bash
# 메트릭 데이터 들어오나?
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=up{namespace="order"}' | jq '.data.result'
```

기대: 모든 서비스의 `up=1` (notification-service는 healthz 가 200 이라 up=1 일 수도, 실제 로직은 Kafka 안 붙어 다운).

## 학습 확인 질문

1. notification-service 의 CrashLoopBackOff 가 정상인 이유는?
2. order-service 가 user-service 를 호출할 때 사용하는 DNS 이름은?
3. ALB 의 Target Group 에 등록된 Pod IP 는 어떤 NS 의 Pod 인가?

다음: [lab-03-end-to-end.md](./lab-03-end-to-end.md)
