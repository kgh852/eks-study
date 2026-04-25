# Lab 02 — CPU 트리거 ScaledObject

## 1. 적용

```bash
kubectl apply -f manifests/cpu-scaler.yaml
kubectl get scaledobject,hpa,deploy
```

기대:
```
NAME                              SCALETARGETKIND  SCALETARGETNAME  ACTIVE  AGE
scaledobject.keda.sh/cpu-demo     Deployment       cpu-demo         True    10s

NAME                                          REFERENCE
horizontalpodautoscaler.autoscaling/keda-hpa-cpu-demo  Deployment/cpu-demo
```

→ KEDA 가 자동으로 HPA 를 만듦 (`keda-hpa-<scaledobject-name>`).

## 2. 부하 확인 (stress 가 자체적으로 CPU 100% 발생시킴)

watch:
```bash
watch -n3 'kubectl get hpa keda-hpa-cpu-demo; echo; kubectl get pods -l app=cpu-demo'
```

기대 (1~3분 후):
```
NAME                  REFERENCE             TARGETS    MINPODS  MAXPODS  REPLICAS
keda-hpa-cpu-demo     Deployment/cpu-demo   95%/50%    1        10       4    ← 스케일 업

NAME                          STATUS
cpu-demo-xxx-aaa              Running
cpu-demo-xxx-bbb              Running
cpu-demo-xxx-ccc              Running
cpu-demo-xxx-ddd              Running
```

## 3. stress 명령 종료 시 (5분 후 자동 종료)

stress 컨테이너의 `--timeout 300s` 가 끝나면 CPU 0% → KEDA cooldown 1분 후 → 1 replica 로 축소.

또는 강제 부하 종료:
```bash
kubectl exec -it deploy/cpu-demo -- pkill stress 2>&1 || true
```

watch 화면:
```
TARGETS    REPLICAS
20%/50%    4
20%/50%    3
20%/50%    2
20%/50%    1     ← 다시 minReplicaCount
```

## 4. ScaledObject 살펴보기

```bash
kubectl describe scaledobject cpu-demo
```

`Status` 에서 트리거 메트릭 / HPA 이름 확인.

## 5. 정리

```bash
kubectl delete -f manifests/cpu-scaler.yaml
```

## 학습 확인 질문

1. KEDA 가 만든 HPA 의 이름 패턴은?
2. ScaledObject 를 삭제하면 자동 생성된 HPA 와 Deployment 는 어떻게 되는가?
3. CPU/Memory 트리거는 metrics-server 가 필요한가?

다음: [lab-03-cron-scaler.md](./lab-03-cron-scaler.md)
