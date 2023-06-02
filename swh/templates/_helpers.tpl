{{/*
Create a global storage configuration based on configuration section aggregation
*/}}
{{- define "swh.storageConfiguration" -}}
{{- $Values := index . 0 -}}
{{- $top := index . 1 -}}
{{- $storageConfigurationRef := index . 2 -}}
{{- $storageConfiguration := get $Values $storageConfigurationRef -}}
{{- if not $storageConfiguration -}}{{ fail (print "Undeclared " $storageConfigurationRef " storage configuration" )}}{{- end -}}
{{- $pipelineStepsRef := get $storageConfiguration "pipelineStepsRef" -}}
{{- $storageServiceConfigurationRef := get $storageConfiguration "storageConfigurationRef" -}}
{{- if not $storageServiceConfigurationRef -}}{{ fail (print "key storageConfigurationRef is mandatory in " $storageConfigurationRef)}}{{- end -}}
{{- $storageServiceConfiguration := get $Values $storageServiceConfigurationRef -}}
{{- $storageType := get $storageServiceConfiguration "cls" -}}
{{- $objectStorageConfigurationRef :=  get $storageConfiguration "objectStorageConfigurationRef" -}}
{{- $journalWriterConfigurationRef := get $storageConfiguration "journalWriterConfigurationRef" -}}
{{- $indent := 2 -}}
storage:
{{ if $pipelineStepsRef -}}
{{- $pipelineSteps := get $Values $pipelineStepsRef -}}
{{- if not $pipelineSteps -}}
  {{ fail (print "No pipeline steps configuraton found:" $pipelineStepsRef) }}
{{- end }}  cls: pipeline
  steps:
{{ toYaml $pipelineSteps | indent 2 }}
{{ end -}}
{{- if eq $storageType "remote" -}}
{{ include "swh.storage.remote" (list $Values $storageServiceConfigurationRef $pipelineStepsRef) | indent $indent }}
{{- else if eq $storageType "cassandra" -}}
{{ include "swh.storage.cassandra" (list $Values $storageServiceConfigurationRef $pipelineStepsRef) | indent $indent }}
{{- else -}}
{{- fail (print "Storage " $storageType " not implemented") -}}
{{- end -}}
{{- if $objectStorageConfigurationRef -}}
{{- $objectStorageConfiguration := get $Values $objectStorageConfigurationRef -}}
{{- $objectStorageType := get $objectStorageConfiguration "cls" -}}
{{- if eq $objectStorageType "noop" }}
{{ include "swh.objstorage.noop" . | indent (int (add 2 $indent)) }}
{{- else -}}
{{- fail (print "Object Storage " $objectStorageType " not implemented") -}}
{{- end -}}
{{- end -}}
{{- if $journalWriterConfigurationRef }}
{{ include "swh.storage.journalWriter" (list $Values $journalWriterConfigurationRef )}}
{{- end -}}
{{- end -}}

{{/*
Generate the configuration for a remote storage
*/}}
{{- define "swh.storage.remote" -}}
{{- $Values := index . 0 -}}
{{- $storageConfigurationRef := index . 1 -}}
{{- $inPipeline := index . 2 -}}
{{- $indent := indent (ternary 0 2 (empty $inPipeline)) "" -}}
{{- $storageConfiguration := get $Values $storageConfigurationRef -}}
{{- if $inPipeline -}}- {{ end }}cls: remote
{{ $indent }}url: {{ get $storageConfiguration "host" }}
{{- end -}}

{{/*
Generate the configuration for a cassandra storage
*/}}
{{- define "swh.storage.cassandra" -}}
{{- $Values := index . 0 -}}
{{- $storageConfigurationRef := index . 1 -}}
{{- $inPipeline := index . 2 -}}
{{- $storageConfiguration := get $Values $storageConfigurationRef -}}
{{- $cassandraSeedsRef := get $storageConfiguration "cassandraSeedsRef" -}}
{{- $cassandraSeeds := get $Values $cassandraSeedsRef -}}
{{- $keyspace := required (print "The keyspace property is mandatory in " $storageConfigurationRef)
                    (get $storageConfiguration "keyspace") -}}

{{- $indent := indent (ternary 0 2 (empty $inPipeline)) "" -}}
{{- if $inPipeline -}}- {{ end }}cls: cassandra
{{ $indent }}hosts:
{{ toYaml $cassandraSeeds | indent 2 }}
{{ $indent }}keyspace: {{ $keyspace }}
{{ $indent }}consistency_level: {{ get $storageConfiguration "consistencyLevel" }}
{{- end -}}

{{/*
Generate the configuration for a null object storage
*/}}
{{- define "swh.objstorage.noop" -}}
objstorage:
  cls: noop
{{- end -}}

{{/*
Generate the configuration for a storage journal broker
*/}}
{{- define "swh.storage.journalWriter" -}}
{{- $Values := index . 0 -}}
{{- $journalWriterConfigurationRef := index . 1 -}}
{{- $journalWriterConfiguration := get $Values $journalWriterConfigurationRef -}}
{{- $brokersRef := get $journalWriterConfiguration "kafkaBrokersRef" -}}
{{- $brokers := get $Values $brokersRef -}}
{{- $clientId := required (print "clientId property is mandatory in " $journalWriterConfigurationRef " map") (get $journalWriterConfiguration "clientId") -}}
journal_writer:
  cls: kafka
  brokers:
{{ toYaml $brokers | indent 2 }}
  prefix: {{ get $journalWriterConfiguration "prefix" | default "swh.journal.objects" }}
  client_id: {{ get $journalWriterConfiguration "clientId" }}
  anonymize: {{ get $journalWriterConfiguration "anonymize" | default true }}
{{- $producerConfig := get $journalWriterConfiguration "producerConfig" -}}
{{- if $producerConfig }}
  producer_config:
{{ toYaml $producerConfig | indent 4 }}
{{- end }}
{{- end -}}
