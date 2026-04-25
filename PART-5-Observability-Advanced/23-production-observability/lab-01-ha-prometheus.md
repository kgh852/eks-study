# Lab 01 — Prometheus HA + remote_write

## 1. 현재 replicas 확인

```bash
kubectl get prometheus -n monitoring kps-kube-prometheus-stack-prometheus -o yaml | yq '.spec.replicas'
```

기본 1.

## 2. HA — replicas 2 로 변경

```bash
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set prometheus.prometheusSpec.replicas=2 \
  --set prometheus.prometheusSpec.replicaExternalLabelName=replica
```

`replicaExternalLabelName: replica` 가 핵심 — Prometheus 별로 `replica=A`, `replica=B` 같은 라벨 자동 부여.

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
```

기대:
```
prometheus-kps-kube-prometheus-stack-prometheus-0   2/2   Running
prometheus-kps-kube-prometheus-stack-prometheus-1   2/2   Running
```

## 3. 두 Prometheus 가 같은 데이터 갖는지 확인

```bash
# Pod 0
kubectl port-forward -n monitoring prometheus-kps-...-0 9091:9090 &
# Pod 1
kubectl port-forward -n monitoring prometheus-kps-...-1 9092:9090 &

curl -sG http://localhost:9091/api/v1/query --data-urlencode 'query=up' | jq '.data.result | length'
curl -sG http://localhost:9092/api/v1/query --data-urlencode 'query=up' | jq '.data.result | length'
```

두 결과 비슷한 시계열 수.

## 4. Grafana 가 두 source 보면 중복

대시보드의 패널이 두 시리즈 (replica=A, replica=B) 로 분리됨 → 의도 X.

## 5. 해결 방법 1 — service 가 round-robin 으로 한 Prom 만 골라줌

`kps-kube-prometheus-stack-prometheus` 라는 Service 가 두 Pod 의 selector 로 매칭. 하지만 round-robin 이라 일관 X.

→ 이 방식은 단순 HA 만 (어느 Prom 이 죽어도 다른 게 응답).

## 6. 해결 방법 2 — Thanos sidecar / 또는 dedup proxy

각 Prom 옆에 Thanos sidecar:
```yaml
prometheus.prometheusSpec:
  thanos:
    image: quay.io/thanos/thanos:v0.36.0
    objectStorageConfig: ...
```

Thanos Querier 가 두 sidecar 를 통합 → 중복 자동 dedup (replica external label 사용).

## 7. remote_write 로 외부 저장소 push

```yaml
prometheus.prometheusSpec:
  remoteWrite:
    - url: https://central-storage.example.com/api/v1/write
      queueConfig:
        maxSamplesPerSend: 1000
        maxShards: 200
        capacity: 2500
```

각 클러스터 Prom 이 자기 데이터를 push → 중앙에서 통합.

## 8. 학습 환경에서는

학습 클러스터 1개라 HA 의 가치 적음. 대신 Thanos / AMP 의 학습 의미가 큼 → 다음 lab.

## 9. 원복

```bash
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set prometheus.prometheusSpec.replicas=1
```

## 학습 확인

1. `replica` external label 의 역할은?
2. 두 Prom 이 정확히 같은 시각에 같은 target 을 scrape 하는가? 차이가 만드는 효과?
3. Thanos sidecar 의 두 가지 책임은?

다음: [lab-02-amp.md](./lab-02-amp.md)
