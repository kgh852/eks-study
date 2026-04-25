# Lab 03 — Cron 트리거 + Scale-to-Zero

## 학습 확인 포인트

- [ ] Pod 가 0 인 상태를 봤다 (HPA 만으로는 불가능)
- [ ] Cron 시간이 되면 자동으로 Pod 가 켜짐
- [ ] 시간 끝나면 다시 0 으로

## 1. 적용

```bash
kubectl apply -f manifests/cron-scaler.yaml
kubectl get deploy cron-demo            # replicas=0
kubectl get scaledobject cron-demo
```

## 2. 처음엔 0 인지 확인

```bash
kubectl get pods -l app=cron-demo
```

기대: `No resources found`. 노드 자원 0 점유.

## 3. Cron 시간 도래

이 ScaledObject 의 `start: "*/5 * * * *"` 는 매 5분의 0초마다 트리거. 5분 단위로 watching:
```bash
watch -n5 'date; kubectl get deploy cron-demo; kubectl get pods -l app=cron-demo'
```

매 5분의 0초 ~ 1분 까지 (즉 각 5분 cycle 의 첫 1분 동안) Pod 가 3개로 켜졌다가 다시 0으로.

## 4. 다른 사용 사례

### 4.1 운영 시간 외 비활성

```yaml
triggers:
  - type: cron
    metadata:
      timezone: Asia/Seoul
      start: "0 9 * * mon-fri"      # 평일 09:00 켜짐
      end: "0 18 * * mon-fri"        # 18:00 꺼짐
      desiredReplicas: "10"
```

→ 업무 시간엔 10개, 그 외엔 0.

### 4.2 야간 배치 작업 시간 고정

```yaml
triggers:
  - type: cron
    metadata:
      start: "0 2 * * *"          # 매일 02:00
      end: "0 4 * * *"             # 04:00
      desiredReplicas: "20"
```

## 5. 다중 트리거 결합

```yaml
triggers:
  - type: cron
    metadata: {start: "0 9 * * mon-fri", end: "0 18 * * mon-fri", desiredReplicas: "5"}
  - type: cpu
    metricType: Utilization
    metadata: {value: "70"}
```

→ 업무 시간엔 항상 5개 + CPU 70% 넘으면 더 늘림.

## 6. 정리

```bash
kubectl delete -f manifests/cron-scaler.yaml
```

## 학습 확인 질문

1. KEDA 가 Pod 를 0 으로 줄이는 메커니즘은?
2. `cooldownPeriod` 가 의미하는 것은?
3. 두 cron trigger (start1+end1, start2+end2) 를 동시에 두면?

다음: [lab-04-prometheus-scaler.md](./lab-04-prometheus-scaler.md)
