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
parameters:
  - name (mandatory): Base name of the autoscaling objects
  - autoscalingConfiguration (mandatory): Dict with the autoscaling configuration (maxReplicaCount, ..)
  - journalClientConfigurationRef (mandatory): pointer to the journalClient configuration
  - journalClientOverrides (mandatory): Dict with some configuration overrides, can be en empty dict
*/}}
{{- define "swh.journalClient.autoscaler" -}}
{{- $journalClientBaseConfiguration := required (print "journalClientConfigurationRef '" .journalClientConfigurationRef "' not found") (get .Values .journalClientConfigurationRef) -}}
{{- $journalClientConfiguration := deepCopy $journalClientBaseConfiguration }}
{{- $journalClientConfiguration := mustMergeOverwrite $journalClientConfiguration .journalClientOverrides -}}
{{- $brokersConfigurationRef := $journalClientConfiguration.brokersConfigurationRef -}}
{{- $brokers := get .Values $brokersConfigurationRef -}}
{{- $_ := set $journalClientConfiguration "brokers" $brokers -}}
{{- $_ := unset $journalClientConfiguration "brokersConfigurationRef" -}}
{{- $_ := required (print "group_id property is mandatory in <" .journalClientConfigurationRef "> map") (get $journalClientConfiguration "group_id") -}}
{{- include "swh.keda.kafkaAutoscaler" (dict
                                "name" .name
                                "kafkaConfiguration" $journalClientConfiguration
                                "autoscalingConfiguration" .autoscalingConfiguration
                                "Values"        .Values) -}}
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
  {{- if hasKey .autoscalingConfiguration "advancedKedaConfig" }}
  advanced: {{ .autoscalingConfiguration.advancedKedaConfig | toYaml | nindent 4 }}
  {{ end -}}
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: {{ join "," .kafkaConfiguration.brokers }}
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

{{/*
   * Create a kind TriggerAuthentication & ScaledObject for celery
   *
   * params:
   *   name (str)          : Service Name (e.g. cooker-simple, ...)
   *   configuration (dict): Full Service configuration dict
   *   Values (dict)       : Global dict of values
   */}}
{{- define "swh.keda.celeryAutoscaler" -}}
{{- $autoscalingConfig := .configuration.autoScaling -}}
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: amqp-authentication-{{ .name }}
  namespace: {{ .Values.namespace }}
spec:
  secretTargetRef:
  - parameter: host            # "host" is required by the scalerObject trigger metadata
    name: common-secrets
    key: rabbitmq-http-host

---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ .name }}-operators
  namespace: {{ .Values.namespace }}
spec:
  scaleTargetRef:
    apiVersion:    apps/v1     # Optional. Default: apps/v1
    kind:          Deployment  # Optional. Default: Deployment
    # Mandatory. Must be in same namespace as ScaledObject
    name:          {{ .name }}
    # envSourceContainerName: {container-name} # Optional. Default:
                                               # .spec.template.spec.containers[0]
  pollingInterval:  30                         # Optional. Default: 30 seconds
  cooldownPeriod:   {{ get $autoscalingConfig "cooldownPeriod" | default 300 }}
                                               # ^ Optional. Default: 300 seconds
  {{- if or (not (hasKey $autoscalingConfig "stopWhenNoActivity"))
            (get $autoscalingConfig "stopWhenNoActivity") }}
  idleReplicaCount: 0                          # Set to 0 to stop all the workers when
                                               # there is no activity on the queue
  {{- end }}
  minReplicaCount:  {{ get $autoscalingConfig "minReplicaCount" | default 0 }}
  maxReplicaCount:  {{ get $autoscalingConfig "maxReplicaCount" | default 5 }}
  triggers:
    {{- range $queue := get .configuration "queues" }}
  - type: rabbitmq
    authenticationRef:
      name: amqp-authentication-{{ $.name }}
    metadata:
      protocol: auto                 # Optional. Specifies protocol to use,
                                     # either amqp or http, or auto to
                                     # autodetect based on the `host` value.
                                     # Default value is auto.
      mode: QueueLength              # QueueLength to trigger on number of msgs in queue
      excludeUnacknowledged: "false" # QueueLength should include unacked messages
                                     # Implies "http" protocol is used
      value: {{ get $autoscalingConfig "queueThreshold" | default 10 | quote }}
      queueName: {{ $queue }}
      vhostName: /                   # Optional. If not specified, use the vhost in the
                                     # `host` connection string. Alternatively, you can
                                     # use existing environment variables to read
                                     # configuration from: See details in "Parameter
                                     # list" section hostFromEnv: RABBITMQ_HOST%
    {{- end }}
{{ end }}
