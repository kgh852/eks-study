# Lab 04 — Alertmanager 라우팅 / 억제 / 묵음

## 1. AlertmanagerConfig CRD 적용

(실제 PagerDuty / Slack 키 없이 manifest 만 점검)

```bash
kubectl apply -f manifests/alertmanager-config.yaml
kubectl get alertmanagerconfig -n monitoring
```

> 실제 통지를 받으려면 Secret 으로 PagerDuty integration key / Slack webhook URL 생성 필요. 학습용은 webhook.site 사용.

## 2. Webhook receiver 임시 셋업 (학습용)

webhook.site 에서 unique URL 받아 다음 receiver 의 url 교체:
```yaml
receivers:
  - name: default-webhook
    webhookConfigs:
      - url: https://webhook.site/<unique-id>
        sendResolved: true
```

## 3. Alertmanager UI

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9093 &
```

http://localhost:9093

탭들:
- **Alerts** — 현재 firing
- **Silences** — 묵음
- **Status** — config + cluster
- **Settings** — runtime config

## 4. 묵음 (silence) — 운영 작업 중

배포 시 일시적 alert 차단:

UI 에서:
1. Silences → New silence
2. Matchers: `namespace = order`
3. Duration: 1h
4. Comment: "Deploy 진행 중"
5. Create

또는 CLI (amtool):
```bash
brew install amtool
amtool silence add 'namespace=order' --duration=1h --comment "deploy" \
  --alertmanager.url=http://localhost:9093
```

## 5. 억제 (inhibition) 시연

위 config 의 inhibit_rule:
- critical 발생 시 같은 NS+service 의 warning 자동 억제

테스트:
1. critical alert 발생시킴 (예: SLO burn rate fast)
2. 동시에 같은 service 의 warning alert (예: SLO burn rate slow) 도 firing 이지만 통지 X
3. critical resolved 후 warning 통지 (만약 여전히 firing)

## 6. 라우팅 트리 검증

UI → Status → 현재 route 트리.

또는:
```bash
amtool config routes test severity=critical namespace=order \
  --alertmanager.url=http://localhost:9093
```

→ 어느 receiver 로 가는지.

## 7. 그룹화 효과

`groupBy: [alertname, namespace]` — 같은 alert 이름 + NS 면 한 그룹 → 1번 통지에 포함.

`groupWait: 30s` — 첫 alert 후 30s 동안 같은 그룹 모음.
`groupInterval: 5m` — 그룹 안 새 alert 추가 시 5m 마다 통지.
`repeatInterval: 4h` — 같은 alert 가 계속 firing 이면 4h 마다 재통지.

## 8. Runbook 패턴 검증

annotation 의 `runbook_url` 이 통지 메시지에 포함되는지 webhook 응답에서 확인:
```json
{
  "alerts": [{
    "labels": {"alertname": "OrderServiceSLOBurnRateFast", "severity": "critical"},
    "annotations": {
      "summary": "...",
      "runbook_url": "https://wiki.example.com/runbooks/slo-burn"
    }
  }]
}
```

→ Slack notification template 에 link 포함하면 on-call 이 즉시 절차 확인.

## 9. 정리

```bash
kubectl delete -f manifests/alertmanager-config.yaml
```

## 학습 확인

1. group_wait 와 group_interval 의 차이는?
2. inhibition vs silence 의 차이는?
3. continue: true 가 있는 route 의 효과는?

다음: [quiz.md](./quiz.md)
