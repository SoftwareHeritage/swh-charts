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
{{- else if eq $storageType "postgresql" -}}
{{ include "swh.storage.postgresql" (list $Values $storageServiceConfigurationRef $pipelineStepsRef) | indent $indent }}
{{- else -}}
{{- fail (print "Storage " $storageType " not implemented") -}}
{{- end -}}
{{/* TODO: specific_options */}}
{{- if $objectStorageConfigurationRef -}}
{{- $objectStorageIndent := ternary $indent (int (add $indent 2)) (empty $pipelineStepsRef) -}}
{{- $objectStorageConfiguration := get $Values $objectStorageConfigurationRef -}}
{{- $objectStorageType := get $objectStorageConfiguration "cls" -}}
{{- if eq $objectStorageType "noop" }}
{{ include "swh.objstorage.noop" . | indent $objectStorageIndent }}
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
Create a global scheduler configuration based on scheduler section aggregation
*/}}
{{- define "swh.schedulerConfiguration" -}}
{{- $Values := index . 0 -}}
{{- $schedulerConfigurationRef := index . 1 -}}
{{- $schedulerConfiguration := get $Values $schedulerConfigurationRef -}}
{{- if not $schedulerConfiguration -}}{{ fail (print "key " $schedulerConfigurationRef " is mandatory in global dict $Values")}}{{- end -}}
{{- $schedulerType := get $schedulerConfiguration "cls" -}}
{{- if eq $schedulerType "remote" -}}
{{ include "swh.scheduler.remote" (list $Values $schedulerConfigurationRef) }}
{{- else if eq $schedulerType "postgresql" -}}
{{ include "swh.scheduler.postgresql" (list $Values $schedulerConfigurationRef) }}
{{- else -}}
{{- fail (print "Scheduler " $schedulerType " not implemented") -}}
{{- end -}}
{{- end -}}

{{/*
Generate the configuration for a remote scheduler
*/}}
{{- define "swh.scheduler.remote" -}}
{{- $Values := index . 0 -}}
{{- $schedulerConfigurationRefKey := index . 1 -}}
{{- $schedulerConfiguration := get $Values $schedulerConfigurationRefKey -}}
scheduler:
  cls: {{ get $schedulerConfiguration "cls" }}
  url: http://{{ get $schedulerConfiguration "host" }}:{{ get $schedulerConfiguration "port" }}
{{- end -}}

{{/*
Generate the celery configuration. This will need evolution to deal with more celery
configuration keys.
*/}}
{{- define "celery.configuration" -}}
{{- $Values := index . 0 -}}
{{- $celeryConfigurationRefKey := index . 1 -}}
{{- $celeryConfiguration := get $Values $celeryConfigurationRefKey -}}
{{- $host := required (print "The 'host' property is mandatory in " $celeryConfiguration)
                    (get $celeryConfiguration "host") -}}
{{- $port := required (print "The 'port' property is mandatory in " $celeryConfiguration)
                    (get $celeryConfiguration "port") -}}
{{- $user := required (print "The 'user' property is mandatory in " $celeryConfiguration)
                    (get $celeryConfiguration "user") -}}
{{- $pass := required (print "The 'pass' property is mandatory in " $celeryConfiguration)
                    (get $celeryConfiguration "pass") -}}
celery:
  task_broker: amqp://{{ $user }}:{{ $pass }}@{{ $host }}:{{ $port }}/%2f
{{- end -}}

{{/*
Generate the configuration for a postgresql scheduler
*/}}
{{- define "swh.scheduler.postgresql" -}}
{{- $Values := index . 0 -}}
{{- $schedulerConfigurationRef := index . 1 -}}
{{- $schedulerConfiguration := get $Values $schedulerConfigurationRef -}}
{{- $host := required (print "The host property is mandatory in " $schedulerConfigurationRef)
                    (get $schedulerConfiguration "host") -}}
{{- $port := required (print "The port property is mandatory in " $schedulerConfigurationRef)
                    (get $schedulerConfiguration "port") -}}
{{- $user := required (print "The user property is mandatory in " $schedulerConfigurationRef)
                    (get $schedulerConfiguration "user") -}}
{{- $password := required (print "The password property is mandatory in " $schedulerConfigurationRef)
                    (get $schedulerConfiguration "password") -}}
{{- $db := required (print "The db property is mandatory in " $schedulerConfigurationRef)
                    (get $schedulerConfiguration "db") -}}
scheduler:
  cls: postgresql
  db: host={{ $host }} port={{ $port }} user={{ $user }} dbname={{ $db }} password={{ $password }}
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
{{- $authProvider := get  $storageConfiguration "authProvider" -}}
{{- $keyspace := required (print "The keyspace property is mandatory in " $storageConfigurationRef)
                    (get $storageConfiguration "keyspace") -}}
{{- $indentationCount := ternary 0 2 (empty $inPipeline) -}}
{{- $indent := indent $indentationCount "" -}}
{{- $nextLevelIndentCount := (int (add $indentationCount 2)) -}}
{{- if $inPipeline -}}- {{ end }}cls: cassandra
{{ $indent }}hosts:
{{ toYaml $cassandraSeeds | indent 2 }}
{{ $indent }}keyspace: {{ $keyspace }}
{{ $indent }}consistency_level: {{ get $storageConfiguration "consistencyLevel" }}
{{ if $authProvider }}{{ $indent }}auth_provider:
{{ toYaml $authProvider | indent $nextLevelIndentCount }}
{{ end -}}
{{ toYaml (get $storageConfiguration "specificOptions") | indent $indentationCount }}
{{- end -}}

{{/*
Generate the configuration for a postgresql storage
*/}}
{{- define "swh.storage.postgresql" -}}
{{- $Values := index . 0 -}}
{{- $storageConfigurationRef := index . 1 -}}
{{- $inPipeline := index . 2 -}}
{{- $storageConfiguration := get $Values $storageConfigurationRef -}}
{{- $host := required (print "The host property is mandatory in " $storageConfigurationRef)
                    (get $storageConfiguration "host") -}}
{{- $port := required (print "The port property is mandatory in " $storageConfigurationRef)
                    (get $storageConfiguration "port") -}}
{{- $user := required (print "The user property is mandatory in " $storageConfigurationRef)
                    (get $storageConfiguration "user") -}}
{{- $password := required (print "The password property is mandatory in " $storageConfigurationRef)
                    (get $storageConfiguration "password") -}}
{{- $db := required (print "The db property is mandatory in " $storageConfigurationRef)
                    (get $storageConfiguration "db") -}}
{{- if (empty $inPipeline) }}
storage:
  cls: postgresql
  db: host={{ $host }} port={{ $port }} user={{ $user }} dbname={{ $db }} password={{ $password }}
{{ else }}
  - cls: postgresql
    db: host={{ $host }} port={{ $port }} user={{ $user }} dbname={{ $db }} password={{ $password }}
{{ end }}
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

{{/* Generate the init keyspace container configuration if needed */}}
{{- define "swh.storage.cassandra.initKeyspaceContainer" -}}
  {{- $Values := index . 0 -}}
  {{- $storageDefinitionRef := index . 1 -}}
  {{- $imageNamePrefix := index . 2 -}}
  {{- $storageDefinition := required (print "Storage definition " $storageDefinitionRef " not found") (get $Values $storageDefinitionRef) -}}
  {{- $storageConfigurationRef := required (print "storageConfigurationRef key needed in " $storageDefinitionRef) (get $storageDefinition "storageConfigurationRef") -}}
  {{- $storageConfiguration := required (print $storageConfigurationRef " declaration not found") (get $Values $storageConfigurationRef) -}}
  {{- $storageClass := required (print "cls entry mandatory in " $storageConfigurationRef) (get $storageConfiguration "cls") -}}

  {{- if eq "cassandra" $storageClass -}}
    {{- $initKeyspace := get $storageConfiguration "initKeyspace" -}}
    {{- if $initKeyspace -}}
      {{- $cassandraSeedsRef := get $storageConfiguration "cassandraSeedsRef" -}}
      {{- $cassandraSeeds := get $Values $cassandraSeedsRef -}}
- name: init-database
  image: {{ get $Values $imageNamePrefix }}:{{ get $Values (print $imageNamePrefix "_version") }}
  imagePullPolicy: Always
  command:
  - /usr/local/bin/python3
  args:
  - /entrypoints/init-keyspace.py
  volumeMounts:
  - name: configuration
    mountPath: /etc/swh
    readOnly: true
  - name: database-utils
    mountPath: /entrypoints
    readOnly: true
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* Generate the storage environment config for database configuration if needed */}}
{{- define "swh.storage.secretsEnvironment" -}}
  {{- $Values := index . 0 -}}
  {{- $storageDefinitionRef := index . 1 -}}
  {{- $storageDefinition := required (print "Storage definition " $storageDefinitionRef " not found") (get $Values $storageDefinitionRef) -}}
  {{- $storageConfigurationRef := required (print "storageConfigurationRef key needed in " $storageDefinitionRef) (get $storageDefinition "storageConfigurationRef") -}}
  {{- $storageConfiguration := required (print $storageConfigurationRef " declaration not found") (get $Values $storageConfigurationRef) -}}
  {{- $secrets := get $storageConfiguration "secrets" -}}
  {{- if $secrets -}}
env:
    {{- range $secretName, $secretsConfig := $secrets }}
- name: {{ $secretName }}
  valueFrom:
    secretKeyRef:
      name: {{ get $secretsConfig "secretKeyRef" }}
      key: {{ get $secretsConfig "secretKeyName" }}
      # 'name' secret must exist & include that ^ key
      optional: false
      {{- end -}}
  {{- end -}}
{{- end -}}

{{/* Generate the check migration container configuration if needed */}}
{{- define "swh.checkDatabaseVersionContainer" -}}
  {{- $Values := index . 0 -}}
  {{- $imageNamePrefix := index . 1 -}}
  {{- $module := index . 2 -}}
- name: check-migration
  image: {{ get $Values $imageNamePrefix }}:{{ get $Values (print $imageNamePrefix "_version") }}
  command:
  - /entrypoints/check-storage-db-version.sh
  env:
  - name: MODULE
    value: {{ $module }}
  volumeMounts:
  - name: configuration
    mountPath: /etc/swh
  - name: database-utils
    mountPath: /entrypoints
{{- end -}}

{{/* Generate the celery config for celery configuration if needed */}}
{{- define "celery.secretsEnvironment" -}}
  {{- $Values := index . 0 -}}
  {{- $celeryDefinitionRef := index . 1 -}}
  {{- $celeryConfiguration := required (print "Celery definition " $celeryDefinitionRef " not found") (get $Values $celeryDefinitionRef) -}}
  {{- $secrets := get $celeryConfiguration "secrets" -}}
  {{- if $secrets -}}
env:
    {{- range $secretName, $secretsConfig := $secrets }}
- name: {{ $secretName }}
  valueFrom:
    secretKeyRef:
      name: {{ get $secretsConfig "secretKeyRef" }}
      key: {{ get $secretsConfig "secretKeyName" }}
      # 'name' secret must exist & include that ^ key
      optional: false
      {{- end -}}
  {{- end -}}
{{- end -}}

{{/* Generate the scheduler environment config for database configuration if needed */}}
{{- define "swh.scheduler.secretsEnvironment" -}}
  {{- $Values := index . 0 -}}
  {{- $schedulerDefinitionRef := index . 1 -}}
  {{- $schedulerConfiguration := required (print "Scheduler definition " $schedulerDefinitionRef " not found") (get $Values $schedulerDefinitionRef) -}}
  {{- $secrets := get $schedulerConfiguration "secrets" -}}
  {{- if $secrets -}}
env:
    {{- range $secretName, $secretsConfig := $secrets }}
- name: {{ $secretName }}
  valueFrom:
    secretKeyRef:
      name: {{ get $secretsConfig "secretKeyRef" }}
      key: {{ get $secretsConfig "secretKeyName" }}
      # 'name' secret must exist & include that ^ key
      optional: false
      {{- end -}}
  {{- end -}}
{{- end -}}

{{/*
Generate the configuration for a journal configuration key
*/}}
{{- define "swh.journalClientConfiguration" -}}
{{- $Values := index . 0 -}}
{{- $journalConfigurationRef := index . 1 -}}
{{- $journalConfiguration := get $Values $journalConfigurationRef -}}
{{- $brokersRef := required (print "kafkaBrokersRef is mandatory in" $journalConfiguration " map" ) (get $journalConfiguration "kafkaBrokersRef") -}}
{{- $brokers := required (print $brokersRef " is mandatory is mandatory in the global values " $Values " map") (get $Values $brokersRef) -}}
{{- $groupId := required (print "groupId property is mandatory in " $journalConfigurationRef " map") (get $journalConfiguration "groupId") -}}
journal:
  brokers:
{{ toYaml $brokers | indent 2 }}
  group_id: {{ $groupId }}
{{- end -}}
