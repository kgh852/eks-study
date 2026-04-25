# Lab 02 — Kafka 기반 ScaledObject

## 학습 확인 포인트

- [ ] Strimzi Operator 로 Kafka in-cluster 띄움
- [ ] notification-service 가 Kafka topic lag 기반 스케일
- [ ] partition 수와 replicas 한계 이해

## 1. Strimzi Operator 설치

```bash
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  -n kafka --create-namespace \
  --set watchAnyNamespace=true \
  --wait

kubectl get pods -n kafka
```

기대:
```
strimzi-cluster-operator-xxx   1/1   Running
```

## 2. Kafka 클러스터 + Topic 생성

```bash
kubectl apply -f manifests/strimzi-kafka.yaml

# 약 2~3분 후 Ready
kubectl wait --for=condition=Ready kafka/my-cluster -n kafka --timeout=300s
kubectl get kafka,kafkanodepool,kafkatopic -n kafka
```

기대:
```
NAME                                READY   ...
kafka.kafka.strimzi.io/my-cluster   True    ...

NAME                       READY
kafkanodepool/dual-role    True

NAME                                          PARTITIONS  REPLICATION
kafkatopic.kafka.strimzi.io/notifications     3           1
```

## 3. notification-service 의 KAFKA_BROKERS 갱신

```bash
kubectl set env deploy/notification-service -n order \
  KAFKA_BROKERS=my-cluster-kafka-bootstrap.kafka:9092 \
  KAFKA_TOPIC=notifications \
  KAFKA_GROUP=notification-service

kubectl rollout status deploy/notification-service -n order
```

→ 이전 모듈 09 에서 CrashLoop 였던 notification-service 가 정상 Running.

## 4. ScaledObject 적용

```bash
kubectl apply -f manifests/kafka-scaledobject.yaml
kubectl get scaledobject -n order
```

## 5. 0 으로 줄어드는지 watch

```bash
watch -n3 'kubectl get hpa -n order keda-hpa-notification-service; kubectl get pods -n order -l app.kubernetes.io/name=notification-service'
```

기대 (cooldown 후): replicas=0.

## 6. Kafka topic 에 메시지 produce

```bash
# 임시 producer Pod
kubectl run kafka-producer --rm -it --image=confluentinc/cp-kafka:7.6.0 \
  -n kafka \
  --command -- bash -c "for i in \$(seq 1 500); do echo '{\"to\":\"u'\$i'\",\"msg\":\"hello'\$i'\"}'; done | kafka-console-producer.sh --broker-list my-cluster-kafka-bootstrap:9092 --topic notifications"
```

→ 500 건 produce.

## 7. lag 폭증 → 스케일 업 관찰

watch:
```
HPA TARGETS         REPLICAS
... 500/10          3     ← max=3 (partition 수)
```

> 중요: replicas 가 partition 수(3)를 넘지 못함. 4번째 Pod 는 만들어져도 idle.

## 8. lag 모니터 (선택)

```bash
kubectl exec -n kafka my-cluster-kafka-0 -- bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-service
```

기대 컬럼:
- `CURRENT-OFFSET`: 컨슈머가 처리한 위치
- `LOG-END-OFFSET`: 토픽의 가장 최근 위치
- `LAG`: 차이

## 9. 처리 완료 후 0 으로

5 분 후 lag 가 임계 미만 → cooldown → 0.

## 10. 정리

```bash
kubectl delete -f manifests/kafka-scaledobject.yaml
kubectl delete -f manifests/strimzi-kafka.yaml -n kafka
helm uninstall strimzi-kafka-operator -n kafka
kubectl delete ns kafka
```

## 학습 확인 질문

1. Kafka topic 의 partition 수와 KEDA maxReplicaCount 관계는?
2. 큐 처리 속도가 빠른데 Pod 수가 너무 많이 늘어나면? (over-scaling 방지)
3. Strimzi 가 만드는 Kafka NodePool / Kafka 리소스의 차이는?

다음: [quiz.md](./quiz.md)
