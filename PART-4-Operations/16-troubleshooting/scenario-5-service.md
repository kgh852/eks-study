# 시나리오 5 — Service 호출 무응답

## 1. 재현

Service 의 selector 를 의도적으로 잘못 설정:
```bash
kubectl create deploy svc-test --image=nginx --replicas=2
kubectl expose deploy svc-test --port=80 --selector=app=does-not-exist
sleep 10
```

## 2. 증상

```bash
kubectl run -it --rm dbg --image=alpine -- sh -c "apk add -q curl && curl -m 5 http://svc-test/ && echo OK"
```

기대:
```
curl: (28) Connection timed out after 5001 milliseconds
```

## 3. 진단 절차

### 3.1 Endpoints 확인

```bash
kubectl get endpoints svc-test
```

기대:
```
NAME       ENDPOINTS   AGE
svc-test   <none>      1m
```

→ Endpoints 가 비어있음. **이게 핵심 단서**.

### 3.2 Service selector 확인

```bash
kubectl get svc svc-test -o yaml | yq '.spec.selector'
```

기대:
```yaml
app: does-not-exist
```

### 3.3 실제 Pod 의 라벨 확인

```bash
kubectl get pods --show-labels | grep svc-test
```

기대:
```
svc-test-xxx   ...   app=svc-test,pod-template-hash=...
```

→ Service 가 찾는 라벨 `app=does-not-exist` 와 Pod 의 라벨 `app=svc-test` 불일치.

## 4. 다른 가능 원인들

| 증상 | 진단 |
|------|------|
| Endpoints 있는데 timeout | Pod readinessProbe 실패 → Endpoints 에서 자동 제외 |
| ClusterIP 자체에 응답 없음 | kube-proxy 죽음 (`kubectl get pods -n kube-system -l k8s-app=kube-proxy`) |
| DNS 해석 실패 | CoreDNS Pod 상태 |
| Cross-NS 호출 안 됨 | FQDN 사용 여부 (`<svc>.<ns>.svc.cluster.local`) |

## 5. 해결

```bash
# 셀렉터 수정
kubectl patch svc svc-test --type=merge -p '{"spec":{"selector":{"app":"svc-test"}}}'

# 다시 호출
kubectl run -it --rm dbg --image=alpine -- sh -c "apk add -q curl && curl -m 5 http://svc-test/ | head -3"
```

## 6. 정리

```bash
kubectl delete deploy svc-test
kubectl delete svc svc-test
```

## 학습 확인

- Endpoints 가 자동 갱신되는 trigger 는?
- readinessProbe 가 실패한 Pod 가 Endpoints 에서 제외되는 동작이 의미하는 것은?
- Service의 selector 와 Pod 의 라벨이 일치한다고 가정할 때, Endpoints 가 비어있을 또 다른 원인은?
