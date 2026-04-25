# Lab 02 — AWS Managed Prometheus (AMP) 연결

## ⚠️ 비용

AMP 는 ingestion + query 별 과금. 학습 1~2시간 ~$0.1 ~ $0.5.

## 1. AMP Workspace 생성

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

aws amp create-workspace --alias eks-study --region $REGION

WORKSPACE_ID=$(aws amp list-workspaces --query 'workspaces[?alias==`eks-study`]|[0].workspaceId' --output text --region $REGION)
echo "Workspace: $WORKSPACE_ID"

REMOTE_WRITE_URL="https://aps-workspaces.${REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}/api/v1/remote_write"
QUERY_URL="https://aps-workspaces.${REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}"
```

## 2. IRSA 셋업 — Prometheus 가 AMP 에 write

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=monitoring \
  --name=amp-iamproxy-ingest-service-account \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess \
  --override-existing-serviceaccounts \
  --approve --region=$REGION
```

## 3. Prometheus 의 remote_write 활성화

```bash
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set "prometheus.prometheusSpec.remoteWrite[0].url=${REMOTE_WRITE_URL}" \
  --set "prometheus.prometheusSpec.remoteWrite[0].sigv4.region=${REGION}" \
  --set "prometheus.serviceAccount.create=false" \
  --set "prometheus.serviceAccount.name=amp-iamproxy-ingest-service-account"
```

`sigv4.region` 으로 AWS Sigv4 인증 자동 처리.

## 4. 데이터 흐름 확인

Prometheus 로그:
```bash
kubectl logs -n monitoring prometheus-kps-...-0 -c prometheus --tail=20 | grep -i remote
```

기대: `remote_write` 관련 로그, 401/403 없으면 정상.

## 5. AMP 직접 쿼리

```bash
# CLI 로 sigv4 인증 쿼리
curl --aws-sigv4 "aws:amz:${REGION}:aps" \
  --user "$(aws configure get aws_access_key_id):$(aws configure get aws_secret_access_key)" \
  -G "${QUERY_URL}/api/v1/query" \
  --data-urlencode 'query=up' \
  | jq '.data.result | length'
```

기대: 양수 (Prometheus 가 push 한 메트릭).

## 6. Grafana 에서 AMP 를 datasource 로 추가

Grafana → Configuration → Data sources → Add data source → Prometheus.

- URL: `${QUERY_URL}`
- Auth: SigV4 (Default region: $REGION)
- Save & test

→ 기존 in-cluster Prometheus + AMP 둘 다 사용 가능.

## 7. Prometheus 자체 retention 줄이기 (AMP 가 장기 저장)

```bash
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set prometheus.prometheusSpec.retention=12h
```

→ 로컬은 12시간만, AMP 가 15개월. 디스크 절감.

## 8. 정리 (학습 끝)

```bash
# remote_write 제거
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set "prometheus.prometheusSpec.remoteWrite=null"

# AMP workspace 삭제 (비용 정지)
aws amp delete-workspace --workspace-id $WORKSPACE_ID --region $REGION
```

## 학습 확인

1. AMP 의 retention 은? Prometheus 자체 retention 과의 관계?
2. sigv4 인증의 흐름은?
3. AMP 비용 모델 (어떤 동작이 비용을 만드나)?

다음: [lab-03-slo-alerts.md](./lab-03-slo-alerts.md)
