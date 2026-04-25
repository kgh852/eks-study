# Lab 03 — Federation 시연

## 1. /federate endpoint 확인

```bash
curl -sG http://localhost:9090/federate \
  --data-urlencode 'match[]={__name__="up"}' \
  | head -10
```

기대:
```
# TYPE up untyped
up{instance="...",job="..."} 1 1700000000123
up{instance="...",job="kube-state-metrics"} 1 ...
```

→ 다른 Prometheus 가 이 endpoint 를 scrape 하면 메트릭을 그대로 받음.

## 2. 가상 시나리오 — 이 클러스터 외에 다른 Prometheus 가 federate 한다고 가정

다른 Prometheus 의 scrape 설정 예시:
```yaml
scrape_configs:
  - job_name: 'federate-eks-study'
    scrape_interval: 30s
    honor_labels: true
    metrics_path: '/federate'
    params:
      'match[]':
        - '{job=~".+"}'
        - 'up'
        - '{__name__=~"http_request.+"}'
    static_configs:
      - targets:
          - 'eks-study-prom.example.com:9090'
```

`honor_labels: true` 가 핵심 — 원본 Prometheus 의 라벨 보존.

## 3. Federation 의 한계

- 메트릭 양이 크면 /federate 응답이 거대 (수 MB 이상)
- 자체 TSDB 라 장기 저장 어려움
- 중복 시계열 (같은 메트릭이 두 Prometheus 에서)

→ **현대적 대안** — `remote_write`:
```yaml
prometheus.spec:
  remoteWrite:
    - url: https://remote-storage.example.com/api/v1/write
```

원격 저장소 (Thanos, Mimir, AMP) 로 메트릭 push.

## 4. Multi-Cluster 패턴 비교

| 패턴 | 특징 |
|------|------|
| **Federation** | 각 클러스터 Prom + 중앙 Prom 가 /federate 로 가져옴 |
| **remote_write** | 각 클러스터 Prom 이 중앙 storage 로 push |
| **Single Prometheus + multi-cluster scrape** | 한 Prom 가 여러 클러스터의 endpoint 직접 scrape (네트워킹 복잡) |
| **Thanos sidecar** | 각 Prom 옆에 Thanos sidecar → S3 로 저장 → 중앙 Querier 가 통합 |

본 커리큘럼 다음 모듈 (Module 23) 에서 Thanos / AMP 도입.

## 5. AWS Managed Prometheus (AMP) 미리보기

remote_write 로 AMP 에 보내는 패턴:
```yaml
remoteWrite:
  - url: https://aps-workspaces.${REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}/api/v1/remote_write
    sigv4:
      region: ${REGION}
    queueConfig:
      maxSamplesPerSend: 1000
      maxShards: 200
      capacity: 2500
```

AMP 의 장점:
- 무한 retention (15개월)
- HA 자동
- AWS IAM 으로 인증 (sigv4)

비용: ingestion + query 별 과금.

## 학습 확인

1. /federate 와 remote_write 의 결정적 차이는?
2. honor_labels 가 false 면 무슨 일이 벌어지나?
3. Prometheus 자체 retention 을 30일로 했을 때 한계는?

다음: [quiz.md](./quiz.md)
