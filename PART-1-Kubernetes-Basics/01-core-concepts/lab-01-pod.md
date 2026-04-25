# Lab 01 — 첫 Pod 배포

## 학습 확인 포인트

- [ ] Imperative vs Declarative 차이를 안다
- [ ] Pod의 라이프사이클 단계를 본 적이 있다
- [ ] `kubectl describe pod` 으로 이벤트를 읽을 수 있다

## 1. Imperative — 명령어로 즉시 띄우기

```bash
kubectl run hello-imperative --image=nginx:1.27 --port=80
```

확인:
```bash
kubectl get pods
kubectl get pod hello-imperative -o wide
```

기대:
```
NAME                READY   STATUS    RESTARTS   AGE
hello-imperative    1/1     Running   0          15s
```

## 2. Declarative — YAML로 띄우기 (실무 표준)

```bash
kubectl apply -f manifests/pod.yaml
```

같은 결과지만, **YAML 파일이 곧 인프라의 단일 소스 오브 트루스**가 됩니다. 이게 실무 표준.

```bash
kubectl get pods
```

기대:
```
NAME                READY   STATUS    RESTARTS   AGE
hello-pod           1/1     Running   0          10s
hello-imperative    1/1     Running   0          1m
```

## 3. 상세 정보 보기

### Describe — 사람이 읽기 쉬운 형태

```bash
kubectl describe pod hello-pod
```

주목해서 볼 부분:
- `Events:` 마지막 — 어떤 단계를 거쳤는지 보여줌
- `IP:` — Pod에 할당된 클러스터 내 IP
- `Node:` — 어느 노드에서 실행 중인지
- `Conditions:` — `PodScheduled`, `Ready` 등 상태

### YAML — 머신이 읽는 전체 정의

```bash
kubectl get pod hello-pod -o yaml | less
```

`status:` 부분에 K8s가 채워 넣은 정보가 잔뜩 (할당된 IP, 호스트, 컨테이너 ID 등).

### JSONPath로 특정 필드만

```bash
kubectl get pod hello-pod -o jsonpath='{.status.podIP}'
echo  # 줄바꿈
kubectl get pod hello-pod -o jsonpath='{.spec.nodeName}'
```

## 4. 로그와 셸

### 로그 보기

```bash
kubectl logs hello-pod
kubectl logs hello-pod -f    # 실시간 follow
```

### 셸로 진입

```bash
kubectl exec -it hello-pod -- sh
# 안에서:
ls /
hostname
exit
```

## 5. Pod 안에서 테스트

```bash
# 다른 디버그 Pod 띄워서 hello-pod에 접근
kubectl run -it --rm dbg --image=alpine -- sh
# 안에서:
apk add --no-cache curl
curl <hello-pod의 IP>     # describe로 본 IP
exit
```

기대: HTML이 나옴 (nginx 기본 페이지).

## 6. Pod의 단명함 체험

```bash
kubectl delete pod hello-pod
kubectl get pods
```

**Pod가 사라졌습니다.** 자동으로 다시 만들어주는 컨트롤러가 없으면 끝. 이게 다음 lab의 동기.

## 7. 이번 lab 정리

```bash
kubectl delete pod hello-imperative
```

## 학습 확인 질문

1. `kubectl run` 과 `kubectl apply -f` 의 차이를 한 문장으로?
2. `kubectl describe pod` 출력 중 어디를 보면 "왜 Pending에 머물러 있는가" 를 알 수 있을까?
3. Pod가 죽으면 자동으로 살아나지 않는 이유는?

답은 [theory.md §1, §2](./theory.md) 에서.

다음: [lab-02-deployment.md](./lab-02-deployment.md)
