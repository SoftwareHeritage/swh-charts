{{ define "swh.indexer.configmap" }}
{{ $indexer_name := ( print "indexer-" .indexer_type ) }}
{{- $journalUser := .Values.indexers.journalBrokers.user -}}
{{- $consumerGroup := get .deployment_config "consumerGroup" -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $indexer_name }}-configuration-template
  namespace: {{ .Values.namespace }}
data:
  config.yml.template: |
    {{- include "swh.storageConfiguration" (dict "configurationRef" .Values.indexers.storageConfigurationRef
                                                 "Values" .Values ) | nindent 4 }}
    {{- include "swh.schedulerConfiguration" (dict "configurationRef" .Values.indexers.schedulerConfigurationRef
                                                   "Values" .Values) | nindent 4 }}
    {{- include "swh.service.fromYaml" (dict "service" "indexer_storage"
                                             "configurationRef" .Values.indexers.indexerStorageConfigurationRef
                                             "Values" .Values) | nindent 4 }}
    {{- include "swh.service.fromYaml" (dict "service" "objstorage"
                                             "configurationRef" .Values.indexers.objstorageConfigurationRef
                                             "Values" .Values) | nindent 4 }}
    journal:
      brokers: {{ toYaml .Values.indexers.journalBrokers.hosts | nindent 8 }}
      {{ if $journalUser }}
      group_id: {{ $journalUser }}-{{ $consumerGroup }}
      {{ else }}
      group_id: {{ $consumerGroup }}
      {{ end -}}
      prefix: {{ get .deployment_config "prefix" }}
      {{ if .deployment_config.batch_size }}
      batch_size: {{ .deployment_config.batch_size }}
      {{ end -}}

      {{ if $journalUser }}
      sasl.mechanism: SCRAM-SHA-512
      security.protocol: SASL_SSL
      sasl.username: {{ $journalUser }}
      sasl.password: ${BROKER_USER_PASSWORD}
      {{ end -}}

    {{- if .deployment_config.extraConfig -}}
      {{- range $option, $value := .deployment_config.extraConfig }}
    {{ $option }}: {{ toYaml $value | nindent 6 }}
      {{- end }}
    {{- end }}
{{ end }}
