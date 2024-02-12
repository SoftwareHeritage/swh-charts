{{ define "swh.indexer.configmap" }}
{{ $indexer_name := ( print "indexer-" .indexer_type ) }}
{{- $journalClientConfigurationRef := or .deployment_config.journalClientConfigurationRef .Values.indexers.journalClientConfigurationRef -}}
{{- $journalClientConfiguration := required (print "journalClientConfigurationRef '" $journalClientConfigurationRef "' not found in indexers (" .deployment_name ")  configuration") (get .Values $journalClientConfigurationRef) -}}
{{- $journalClientOverrides := deepCopy (get .deployment_config "journalClientOverrides" | default (dict)) -}}
{{- $objstorageConfigurationRef := or .deployment_config.objstorageConfigurationRef .Values.indexers.objstorageConfigurationRef -}}
{{- $storageConfigurationRef := or .deployment_config.storageConfigurationRef .Values.indexers.storageConfigurationRef -}}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $indexer_name }}-configuration-template
  namespace: {{ .Values.namespace }}
data:
  config.yml.template: |
    {{- include "swh.storageConfiguration" (dict "configurationRef" $storageConfigurationRef
                                                 "Values" .Values ) | nindent 4 }}
    {{- include "swh.schedulerConfiguration" (dict "configurationRef" .Values.indexers.schedulerConfigurationRef
                                                   "Values" .Values) | nindent 4 }}
    {{- include "swh.service.fromYaml" (dict "service" "indexer_storage"
                                             "configurationRef" .Values.indexers.indexerStorageConfigurationRef
                                             "Values" .Values) | nindent 4 }}
    {{- include "swh.objstorageConfiguration" (dict "serviceName" "objstorage"
                                             "configurationRef" $objstorageConfigurationRef
                                             "Values" .Values) | nindent 4 }}
    {{- include "swh.journalClientConfiguration" (dict "serviceType" "journal_client" "configurationRef" $journalClientConfigurationRef
                                      "overrides" $journalClientOverrides
                                      "Values" .Values) | nindent 4 }}
    {{- if .deployment_config.extraConfig -}}
      {{- range $option, $value := .deployment_config.extraConfig }}
    {{ $option }}: {{ toYaml $value | nindent 6 }}
      {{- end }}
    {{- end }}
{{ end }}

{{ define "swh.indexer.autoscaling" }}
{{- $journalClientConfigurationRef := or .deployment_config.journalClientConfigurationRef .Values.indexers.journalClientConfigurationRef -}}
{{- $journalClientBaseConfiguration := required (print "journalClientConfigurationRef '" $journalClientConfigurationRef "' not found in indexers (" .deployment_name ")  configuration") (get .Values $journalClientConfigurationRef) -}}
{{- $journalClientOverrides := deepCopy (get .deployment_config "journalClientOverrides" | default (dict)) -}}
{{- $journalClientConfiguration := deepCopy $journalClientBaseConfiguration }}
{{- $journalClientConfiguration := mustMergeOverwrite $journalClientConfiguration $journalClientOverrides -}}
{{- $brokersConfigurationRef := $journalClientConfiguration.brokersConfigurationRef -}}
{{- $brokers := get .Values $brokersConfigurationRef -}}
{{- $_ := set $journalClientConfiguration "brokers" $brokers -}}
{{- $_ := unset $journalClientConfiguration "brokersConfigurationRef" -}}
{{- $_ := required (print "group_id property is mandatory in <" .journalClientConfigurationRef "> map") (get $journalClientConfiguration "group_id") -}}
{{- include "swh.keda.kafkaAutoscaler"
  (dict "name"                     (print "indexer-" .deployment_name)
        "kafkaConfiguration"       $journalClientConfiguration
        "autoscalingConfiguration" .deployment_config.autoScaling
        "Values"                   .Values) }}
{{ end }}
