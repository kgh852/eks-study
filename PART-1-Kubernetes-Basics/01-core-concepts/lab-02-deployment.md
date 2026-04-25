# Lab 02 — Deployment + 롤링 업데이트

## 학습 확인 포인트

- [ ] Deployment → ReplicaSet → Pod 계층을 직접 관찰했다
- [ ] 롤링 업데이트가 어떻게 진행되는지 봤다
- [ ] 롤백을 해봤다

## 1. Deployment 생성

```bash
kubectl apply -f manifests/deployment.yaml
kubectl get deploy,rs,pod -l app=web
```

기대 (조금 기다리면):
```
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/web   3/3     3            3           30s

NAME                             DESIRED   CURRENT   READY   AGE
replicaset.apps/web-7b8c9d6f5    3         3         3       30s

NAME                       READY   STATUS    RESTARTS   AGE
pod/web-7b8c9d6f5-aaaaa    1/1     Running   0          30s
pod/web-7b8c9d6f5-bbbbb    1/1     Running   0          30s
pod/web-7b8c9d6f5-ccccc    1/1     Running   0          30s
```

**관계 확인**:
- Deployment는 1개
- 그 아래 ReplicaSet 1개 (해시 7b8c9d6f5)
- 그 아래 Pod 3개 (모두 같은 ReplicaSet 해시 prefix)

## 2. ReplicaSet의 자가 치유 시연

```bash
kubectl get pods -l app=web
# 임의 pod 하나 골라서 삭제
kubectl delete pod web-7b8c9d6f5-aaaaa
kubectl get pods -l app=web --watch
```

기대: 즉시 새 Pod가 생성되어 다시 3개 유지.

```bash
kubectl describe rs -l app=web | tail -20
```

`Events:` 에서 `Created pod` 가 보입니다.

## 3. 스케일 변경

```bash
kubectl scale deploy/web --replicas=5
kubectl get pods -l app=web
```

기대: Pod가 5개로 늘어남 (점진적 추가).

```bash
kubectl scale deploy/web --replicas=2
kubectl get pods -l app=web
```

기대: Pod가 2개로 줄어듦 (오래된/임의의 Pod부터 삭제).

```bash
kubectl scale deploy/web --replicas=3   # 원래대로
```

## 4. 롤링 업데이트 시연

별도 터미널에서 미리 watch 시작:
```bash
kubectl get pods -l app=web --watch
```

원래 터미널:
```bash
kubectl set image deploy/web nginx=nginx:1.28
kubectl rollout status deploy/web
```

watch 터미널에서 본 흐름:
```
NAME                     READY   STATUS    AGE
web-7b8c9d6f5-aaaaa      1/1     Running   5m
web-7b8c9d6f5-bbbbb      1/1     Running   5m
web-7b8c9d6f5-ccccc      1/1     Running   5m
web-9d4f8a7e2-ddddd      0/1     Pending   0s    ← 새 RS의 Pod 등장
web-9d4f8a7e2-ddddd      0/1     ContainerCreating  1s
web-9d4f8a7e2-ddddd      1/1     Running   5s
web-7b8c9d6f5-aaaaa      1/1     Terminating  ← 옛 RS의 Pod 줄어듦
...
```

새 ReplicaSet이 만들어지고, 옛 ReplicaSet의 Pod가 점진적으로 사라지는 흐름이 보입니다.

```bash
kubectl get rs -l app=web
```

기대 (롤링 업데이트 끝난 후):
```
NAME              DESIRED   CURRENT   READY   AGE
web-7b8c9d6f5     0         0         0       6m  ← 옛 RS, replicas=0
web-9d4f8a7e2     3         3         3       1m  ← 새 RS, replicas=3
```

> **주목**: 옛 ReplicaSet은 사라지지 않습니다. 롤백을 위해 보관됩니다.

## 5. 롤백

```bash
kubectl rollout history deploy/web
```

기대:
```
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

```bash
kubectl rollout undo deploy/web
kubectl rollout status deploy/web
kubectl get rs -l app=web
```

기대: 옛 ReplicaSet의 replicas가 다시 3으로, 새 ReplicaSet은 0으로 → **빠른 롤백**.

## 6. 롤링 업데이트 전략 미세조정

```bash
kubectl get deploy web -o yaml | yq '.spec.strategy'
```

기대:
```yaml
type: RollingUpdate
rollingUpdate:
  maxSurge: 1          # 평소보다 1개 많이까지 가능
  maxUnavailable: 0    # 평소보다 1개도 모자라면 안 됨
```

이 설정이면: 항상 최소 3개는 살아있고, 잠깐 4개까지 됩니다 (안전 우선).
빠르게 굴리고 싶으면 `maxSurge: 50%, maxUnavailable: 50%` 같은 식으로 조정.

## 7. 정리

```bash
kubectl delete -f manifests/deployment.yaml
```

## 학습 확인 질문

1. Deployment를 삭제하면 ReplicaSet과 Pod는 어떻게 될까?
2. `kubectl scale` 과 `kubectl set image` 의 차이를 ReplicaSet 관점에서 설명?
3. `maxUnavailable: 0` 으로 설정하면 어떤 시나리오에서 롤링 업데이트가 멈출 수 있을까?

다음: [lab-03-namespace.md](./lab-03-namespace.md)
