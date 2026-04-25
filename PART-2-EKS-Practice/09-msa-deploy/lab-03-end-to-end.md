# Lab 03 — E2E 트래픽 + 모니터링

## 학습 확인 포인트

- [ ] 부하 발생기를 클러스터 안에서 돌려 봄
- [ ] Grafana 대시보드에서 RPS / 에러율 / latency 확인
- [ ] 로그를 stern 으로 다중 Pod 동시 tail

## 1. 부하 발생기 배포

```bash
ALB_DNS=$(kubectl get ingress -n order msa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

kubectl run loadgen --image=alpine -n order --restart=Always \
  --overrides='{
    "spec": {
      "containers": [{
        "name": "loadgen",
        "image": "alpine:3.19",
        "command": ["sh","-c"],
        "args": ["apk add -q curl && while true; do curl -s -X POST http://'$ALB_DNS'/api/orders -H Content-Type:application/json -d {\"user_id\":\"u1\",\"amount\":100} > /dev/null; sleep 0.1; done"]
      }]
    }
  }'
```

→ 약 10 RPS.

## 2. 메트릭 관찰 (Prometheus)

별도 터미널:
```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
```

브라우저: http://localhost:9090/graph

쿼리 예시:
```
# order-service Pod 의 CPU 사용률
sum(rate(container_cpu_usage_seconds_total{namespace="order",pod=~"order-service.*"}[1m])) by (pod)

# 메모리
sum(container_memory_working_set_bytes{namespace="order",pod=~"order-service.*"}) by (pod)

# 메트릭 endpoint up 상태
up{namespace="order"}
```

## 3. Grafana 대시보드

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80
```

http://localhost:3000 (admin / eks-study-admin).

좌측 → Dashboards → Browse → "Kubernetes / Compute Resources / Namespace (Pods)"
- Namespace: `order`
- 시각: 지난 30분
- Pod 별 CPU / Memory 시각화

## 4. 로그 확인 (stern)

```bash
stern -n order --tail 5 .                 # 모든 Pod
stern -n order order-service              # 특정 패턴
stern -n order -l app.kubernetes.io/name=order-service --since 5m
```

기대: `loadgen` 의 요청이 `order-service` 의 요청 처리 로그로 흐름.

## 5. 부하 종료

```bash
kubectl delete pod loadgen -n order
```

## 6. CloudWatch 로그도 동시에 보내짐 확인

```bash
aws logs tail /aws/containerinsights/eks-study/application \
  --since 5m \
  --filter-pattern '"order-service"' | head -10
```

→ 같은 로그가 CloudWatch Logs 에도 있음 (Container Insights addon 이 설치되어 있다면).

## 7. 회고

이 시점까지 같은 워크로드의 메트릭/로그를:
- **Prometheus** (PromQL 로 쿼리, Grafana 시각화)
- **CloudWatch Logs** (필터 검색)

에서 동시 확인 가능 → **하이브리드 관측 스택** 완성.

## 학습 확인 질문

1. 같은 로그가 Prometheus 에서도 보일까? 안 보인다면 어떤 도구를 추가해야 하나?
2. Grafana 대시보드에서 가장 빠르게 "어떤 Pod가 CPU를 가장 많이 쓰는가?" 를 보려면?
3. 부하가 늘어 Pod이 자동 스케일되게 하려면 무엇을 추가해야 하나?

다음: [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`
