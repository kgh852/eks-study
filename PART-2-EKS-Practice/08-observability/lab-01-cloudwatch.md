# Lab 01 — CloudWatch Container Insights

## ⚠️ 비용

CloudWatch Logs ingestion 은 GB 당 청구. 학습 1~2시간 후 반드시 disable.

## 학습 확인 포인트

- [ ] Container Insights addon 설치
- [ ] CloudWatch 콘솔에서 Container Insights 페이지를 봤다
- [ ] 앱 로그가 CloudWatch Logs로 보내짐을 확인

## 1. IRSA 셋업 (CloudWatch Observability)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=amazon-cloudwatch \
  --name=cloudwatch-agent \
  --attach-policy-arn=arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
  --override-existing-serviceaccounts \
  --approve --region=ap-northeast-2

eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=amazon-cloudwatch \
  --name=fluent-bit \
  --attach-policy-arn=arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy \
  --override-existing-serviceaccounts \
  --approve --region=ap-northeast-2
```

## 2. addon 설치

```bash
eksctl create addon --cluster eks-study \
  --name amazon-cloudwatch-observability \
  --region ap-northeast-2
```

기다리기:
```bash
kubectl get pods -n amazon-cloudwatch --watch
```

기대 (시간 지나면):
```
NAME                              READY   STATUS    RESTARTS   AGE
amazon-cloudwatch-observability-controller-manager-xxx   1/1   Running   0   30s
cloudwatch-agent-aaaaa            1/1   Running   0          20s
cloudwatch-agent-bbbbb            1/1   Running   0          20s
fluent-bit-ccccc                  1/1   Running   0          15s
fluent-bit-ddddd                  1/1   Running   0          15s
```

## 3. CloudWatch Logs Group 확인

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/containerinsights/eks-study/ \
  --query 'logGroups[].logGroupName' --output table
```

기대:
```
/aws/containerinsights/eks-study/application
/aws/containerinsights/eks-study/dataplane
/aws/containerinsights/eks-study/host
/aws/containerinsights/eks-study/performance
```

## 4. 테스트용 앱 로그 발생

```bash
kubectl run logger --image=busybox --restart=Never -- \
  sh -c 'for i in $(seq 1 50); do echo "[INFO] event $i at $(date)"; sleep 1; done'
```

대기:
```bash
sleep 60
```

## 5. CloudWatch Logs 에서 로그 확인

```bash
aws logs tail /aws/containerinsights/eks-study/application \
  --since 5m --filter-pattern '"event"' \
  | head -20
```

기대: `[INFO] event 1 at ...` 같은 로그.

## 6. Container Insights 대시보드 (콘솔)

CloudWatch → Insights → Container Insights → eks-study 선택.

기본 페이지에서 다음을 볼 수 있음:
- 노드별 CPU/Mem
- Pod 별 CPU/Mem 사용량
- Pod restart 횟수
- 네임스페이스별 리소스

## 7. CloudWatch Logs Insights 쿼리

CloudWatch → Logs → Logs Insights → log group 선택 후:

```
fields @timestamp, @message
| filter @message like /event/
| sort @timestamp desc
| limit 50
```

## 8. 정리

```bash
kubectl delete pod logger
```

addon 자체는 다음 lab 이후 일괄 제거 (Module 끝부분).

## 학습 확인 질문

1. Container Insights 가 만든 4개 Logs Group의 차이는?
2. Fluent Bit 가 stdout/stderr 외에 Pod 의 임의 파일도 수집하게 하려면?
3. 비용을 줄이는 방법 두 가지를 들어보세요.

다음: [lab-02-prometheus.md](./lab-02-prometheus.md)
