# 시나리오 4 — OOMKilled

## 1. 재현

```bash
cat > /tmp/oom.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: oom-victim
spec:
  containers:
    - name: stress
      image: progrium/stress
      args: ["--vm", "1", "--vm-bytes", "200M", "--timeout", "300s"]
      resources:
        limits:
          memory: 100Mi          # 의도적으로 작게
EOF
kubectl apply -f /tmp/oom.yaml
sleep 30
```

## 2. 증상

```bash
kubectl get pod oom-victim
```

```
NAME         READY   STATUS              RESTARTS   AGE
oom-victim   0/1     CrashLoopBackOff    2          45s
```

## 3. 진단

```bash
kubectl describe pod oom-victim | grep -A5 'Last State\|Reason\|Exit Code'
```

기대:
```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

`Reason: OOMKilled` + `Exit Code: 137` (SIGKILL by OOM killer) 가 결정적.

## 4. 직전 로그 (있다면)

```bash
kubectl logs oom-victim --previous
```

OOM 직전 메시지 (있다면) 또는 stress 의 출력 일부.

## 5. 메트릭 확인 (Container Insights / Prometheus 가 떠있으면)

```bash
# Prometheus
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
```

```
container_memory_working_set_bytes{pod="oom-victim"}
```

→ limits (104857600 bytes = 100Mi) 에 닿는 순간 OOMKill.

## 6. 해결

```bash
kubectl delete pod oom-victim
```

운영에선:
- limits 를 실제 사용량 기반으로 조정
- 메모리 leak 점검 (heap dump, profiling)
- requests <= 평균, limits >= peak 정도로

> **주의**: requests=limits 가 가장 안전 (Guaranteed QoS). 단 over-provisioning 위험.

## 7. limits 없으면 어떤 일이?

```yaml
resources:
  requests: { memory: 100Mi }
  # limits 없음
```

→ 노드 메모리가 부족할 때 시스템 OOM killer 가 가장 큰 메모리 Pod 부터 종료. 예측 불가능 → **반드시 limits 권장**.

## 학습 확인

- Exit Code 137 의 두 가지 의미는?
- requests > limits 가 가능한가? (NO. 왜?)
- VPA (Vertical Pod Autoscaler) 가 OOM 방지에 도움 되는 시나리오는?
