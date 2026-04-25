# 시나리오 1 — CrashLoopBackOff

## 1. 재현

```bash
kubectl run crashy --image=busybox --restart=Always -- sh -c "echo starting; exit 1"
sleep 30
```

## 2. 증상

```bash
kubectl get pod crashy
```

```
NAME     READY   STATUS              RESTARTS   AGE
crashy   0/1     CrashLoopBackOff    3          1m
```

## 3. 진단 절차

### 3.1 마지막 종료 코드

```bash
kubectl describe pod crashy | grep -A3 'Last State\|State:\|Exit Code\|Reason'
```

기대:
```
State:          Waiting
  Reason:       CrashLoopBackOff
Last State:     Terminated
  Reason:       Error
  Exit Code:    1
```

### 3.2 직전 컨테이너 로그

```bash
kubectl logs crashy --previous
```

기대: `starting` (의도된 출력 + 즉시 종료).

### 3.3 Events

```bash
kubectl get events --sort-by='.lastTimestamp' | tail -10
```

`Back-off restarting failed container` 가 보임.

## 4. 원인 매핑

| Exit Code | 흔한 원인 |
|-----------|-----------|
| 0 | 정상 종료지만 livenessProbe 가 실패로 간주? |
| 1 | 앱 자체 에러 (가장 흔함) |
| 137 | OOMKilled (또는 SIGKILL 받음) |
| 139 | Segmentation fault |
| 143 | SIGTERM (정상 종료 신호 무시) |

이 경우 1 → 앱 자체 에러. 로그가 단서.

## 5. 해결

```bash
# 의도된 시나리오라 그냥 정리
kubectl delete pod crashy
```

실제 운영에선:
- 앱 로그 분석 후 코드 수정
- 환경변수/ConfigMap 누락 점검
- liveness/readiness 설정 검증

## 6. 학습 확인

- `Last State: Terminated` 의 의미는?
- `--previous` 옵션 없이 logs 명령이 실패한다면 그 이유는?
- Exit Code 0 인데 CrashLoop 면 무엇을 의심?
