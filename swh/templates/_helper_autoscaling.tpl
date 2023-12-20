{{/*
Create a kind HorizontalPodAutoscaler for service .serviceType
*/}}
{{- define "swh.autoscale" -}}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  namespace: {{ .Values.namespace }}
  name: {{ .serviceType }}
  labels:
    app: {{ .serviceType }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .serviceType }}
  minReplicas: {{ .configuration.autoScaling.minReplicaCount | default 2 }}
  maxReplicas: {{ .configuration.autoScaling.maxReplicaCount | default 10 }}
  metrics:
  {{- if .configuration.autoScaling.cpuPercentageUsage }}
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .configuration.autoScaling.cpuPercentageUsage }}
  {{- end -}}
{{- end -}}


{{/*
Create a keda's kafka autoscaler
parameters:
  name: Name of the autoscaler
  kafkaConfiguration: kafa configuration as explained in `journalClientConfiguration` in values.yaml
  autoscalingConfiguration: dict that should define poolInterval, lagThreshold, minReplicaCount maxReplicaCount
          all values are optional
  Values: the main values dict
*/}}
{{- define "swh.keda.kafkaAutoscaler" -}}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ .name }}-scaledobject
  namespace: {{ .Values.namespace }}
spec:
  scaleTargetRef:
    name: {{ .name }}
  pollingInterval: {{ get .autoscalingConfiguration "poolInterval" | default 120 }}
  minReplicaCount: {{ get .autoscalingConfiguration "minReplicaCount" | default 1 }}
  maxReplicaCount: {{ get .autoscalingConfiguration "maxReplicaCount" | default 5 }}
  {{ if or (not (hasKey .autoscalingConfiguration "stopWhenNoActivity")) (get .autoscalingConfiguration "stopWhenNoActivity") -}}
  idleReplicaCount: 0
  {{ end -}}
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: {{ first .kafkaConfiguration.brokers }}
      consumerGroup: {{ .kafkaConfiguration.group_id }}
      lagThreshold: {{ get .autoscalingConfiguration "lagThreshold" | default 1000 | quote }}
      offsetResetPolicy: earliest
{{- if hasKey .kafkaConfiguration "sasl.mechanism" -}}
{{- $journalClientConfigurationSecrets := .kafkaConfiguration.secrets -}}
{{- $usernameSecretKey := get .kafkaConfiguration "sasl.username" | replace "${" "" | replace "}" "" -}}
{{- $userSecretDef := get $journalClientConfigurationSecrets $usernameSecretKey -}}
{{- $passwordSecretKey := get .kafkaConfiguration "sasl.password" | replace "${" "" | replace "}" "" -}}
{{- $passwordSecretDef := get $journalClientConfigurationSecrets $passwordSecretKey }}
    authenticationRef:
      name: keda-{{ .name }}-authentication
---
apiVersion: v1
kind: Secret
metadata:
  name: keda-{{ .name }}-secrets
  namespace: {{ .Values.namespace }}
type: Opaque
stringData:
  sasl: "scram_sha512"
  tls: "enable"
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-{{ .name }}-authentication
  namespace: {{ .Values.namespace }}
spec:
  secretTargetRef:
  - parameter: username
    name: {{ $userSecretDef.secretKeyRef }}
    key: {{ $userSecretDef.secretKeyName }}
  - parameter: password
    name: {{ $passwordSecretDef.secretKeyRef }}
    key: {{ $passwordSecretDef.secretKeyName }}
  - parameter: sasl
    name: keda-{{ .name }}-secrets
    key: sasl
  - parameter: tls
    name: keda-{{ .name }}-secrets
    key: tls
{{- end -}}

{{- end -}}
