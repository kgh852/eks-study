# Lab 04 — Prometheus 트리거

## 학습 확인 포인트

- [ ] Prometheus PromQL 쿼리로 외부 메트릭 기반 스케일
- [ ] Module 09 의 order-service 가 떠있는 상태에서 RPS 기반 스케일

## 1. 사전 조건

- Module 08 의 kube-prometheus-stack 떠 있음
- Module 09 의 order-service 가 `order` NS 에 떠 있음

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
kubectl get deploy -n order order-service
```

## 2. ScaledObject 적용

```bash
kubectl apply -f manifests/prom-scaler.yaml
kubectl get scaledobject -n order
```

## 3. 부하 발생 (별도 터미널)

```bash
ALB_DNS=$(kubectl get ingress -n order msa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

kubectl run -it --rm load --image=alpine -- sh -c "
  apk add -q curl &&
  while true; do
    curl -sX POST http://${ALB_DNS}/api/orders \
      -H 'Content-Type: application/json' \
      -d '{\"user_id\":\"u1\",\"amount\":1}' > /dev/null
  done"
```

## 4. Watch — Pod 와 Prometheus 메트릭

```bash
watch -n3 '\
  echo "=== HPA ==="; kubectl get hpa -n order; \
  echo "=== Pods ==="; kubectl get pods -n order -l app.kubernetes.io/name=order-service'
```

기대 (1~3분 후):
```
HPA TARGETS    REPLICAS
... 25/10      ← 25 RPS, threshold 10 → 약 2~3 배
```

Pod 수가 점진적으로 증가.

## 5. PromQL 직접 확인 (Prometheus UI)

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
```

http://localhost:9090/graph 에서:
```
sum(rate(gin_request_duration_seconds_count{namespace="order",pod=~"order-service.*"}[1m]))
```

→ 부하 수준에 따라 그래프 변화.

> 참고: 본 lab 의 PromQL 메트릭 이름(`gin_request_duration_seconds_count`) 은 order-service 의 Gin 미들웨어가 노출하는 표준 메트릭. 실제 메트릭 이름은 `kubectl exec deploy/order-service -- wget -qO- localhost:9090/metrics | head -50` 으로 확인.

## 6. 부하 종료 → cooldown 후 축소

부하 컨테이너 Ctrl+C 종료.

watch 화면:
```
HPA TARGETS    REPLICAS
... 0/10       8
... 0/10       8     ← cooldown 동안 유지
... 0/10       1     ← 60초 후
```

## 7. 정리

```bash
kubectl delete -f manifests/prom-scaler.yaml
```

## 학습 확인 질문

1. KEDA 가 Prometheus 에서 메트릭을 가져오는 빈도는 어디서 설정?
2. PromQL 쿼리가 빈 결과 (NaN) 일 때 ScaledObject 의 동작은?
3. 메트릭 이름이 다른 라이브러리 (Gin → Echo) 로 바뀌면 어떻게 대응?

다음: [quiz.md](./quiz.md)
