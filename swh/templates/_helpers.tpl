# -*- yaml -*-

{{/*
Create a connstring out of a configuration reference.
*/}}
{{- define "swh.connstring" -}}
{{- $configuration := get .Values .configurationRef -}}
{{- $host := required (print "_helpers.tpl:swh.connstring: The <host> property is mandatory in " .configurationRef)
                    (get $configuration "host") -}}
{{- $port := required (print "_helpers.tpl:swh.connstring: The <port> property is mandatory in " .configurationRef)
                    (get $configuration "port") -}}
{{- $user := required (print "_helpers.tpl:swh.connstring: The <user> property is mandatory in " .configurationRef)
                    (get $configuration "user") -}}
{{- $password := required (print "_helpers.tpl:swh.connstring: The <pass> property is mandatory in " .configurationRef)
                    (get $configuration "pass") -}}
{{- $db := required (print "_helpers.tpl:swh.connstring: The <db> property is mandatory in " .configurationRef)
                    (get $configuration "db") -}}
host={{ $host }} port={{ $port }} user={{ $user }} dbname={{ $db }} password={{ $password }}
{{- end -}}

{{/*
Create a global storage configuration based on configuration section aggregation
*/}}
{{- define "swh.storageConfiguration" -}}
{{- $storageConfiguration := get .Values .configurationRef -}}
{{- if not $storageConfiguration -}}
  {{- fail (print "_helpers.tpl: swh.storageConfiguration: Undeclared <" .configurationRef "> storage configuration") -}}
{{- end -}}
{{- $storageServiceConfigurationRef := get $storageConfiguration "storageConfigurationRef" -}}
{{- if not $storageServiceConfigurationRef -}}
  {{- fail (print "_helpers.tpl: swh.storageConfiguration: key <storageConfigurationRef> is mandatory in " .configurationRef) -}}
{{- end -}}
{{- $storageServiceConfiguration := get .Values $storageServiceConfigurationRef -}}
{{- $storageType := get $storageServiceConfiguration "cls" -}}
{{- $storageIncludeArgs := (dict "configurationRef" $storageServiceConfigurationRef "Values" .Values) -}}
{{- $storageConfig := dict -}}
{{- if eq $storageType "remote" -}}
  {{- $storageConfig = mustMergeOverwrite $storageConfig (include "swh.storage.remote" $storageIncludeArgs | fromYaml) -}}
{{- else if eq $storageType "cassandra" -}}
  {{- $storageConfig = mustMergeOverwrite $storageConfig (include "swh.storage.cassandra" $storageIncludeArgs | fromYaml) -}}
{{- else if eq $storageType "postgresql" -}}
  {{- $storageConfig = mustMergeOverwrite $storageConfig (include "swh.postgresql" $storageIncludeArgs | fromYaml) -}}
{{- else -}}
  {{- fail (print "_helpers.tpl:swh.storageConfiguration: Storage <" $storageType "> not implemented") -}}
{{- end -}}

{{- $objstorageConfigurationRef :=  get $storageConfiguration "objstorageConfigurationRef" -}}
{{- if $objstorageConfigurationRef -}}
  {{- $objstorageConfiguration := get .Values $objstorageConfigurationRef -}}
  {{- $objectStorageType := get $objstorageConfiguration "cls" -}}
  {{- $objstorageConfig := include "swh.objstorageConfiguration"
                                   (dict "configurationRef" $objstorageConfigurationRef
                                         "Values" .Values) | fromYaml -}}
  {{- $storageConfig = mustMergeOverwrite $storageConfig $objstorageConfig -}}
{{- end -}}

{{- $journalWriterConfigurationRef := get $storageConfiguration "journalWriterConfigurationRef" -}}
{{- if $journalWriterConfigurationRef -}}
  {{- $journalWriterConfig := include "swh.storage.journalWriter"
                                      (dict "service_type" "journal_writer"
                                            "configurationRef" $journalWriterConfigurationRef
                                            "Values" .Values) | fromYaml -}}
  {{- $storageConfig = mustMergeOverwrite $storageConfig $journalWriterConfig -}}
{{- end -}}

{{- $pipelineStepsRef := get $storageConfiguration "pipelineStepsRef" -}}
{{- if $pipelineStepsRef -}}
  {{- if not (hasKey .Values $pipelineStepsRef) -}}
    {{- fail (print "_helpers.tpl:swh.storageConfiguration: No pipeline steps configuraton found:" $pipelineStepsRef) -}}
  {{- end -}}
  {{- $pipelineSteps := mustAppend (get .Values $pipelineStepsRef | mustDeepCopy) $storageConfig -}}
  {{- $storageConfig = (dict "cls" "pipeline" "steps" $pipelineSteps) -}}
{{- end -}}
{{- dict "storage" $storageConfig | toYaml -}}
{{- end -}}

{{/*
Generate the configuration for a remote storage
*/}}
{{- define "swh.storage.remote" }}
{{- $storageConfiguration := get .Values .configurationRef -}}
{{ (dict "cls" "remote" "url" (get $storageConfiguration "url")) | toYaml }}
{{ end -}}

{{/*
Create a global scheduler configuration based on scheduler section aggregation
*/}}
{{- define "swh.schedulerConfiguration" -}}
{{- $schedulerConfiguration := get .Values .configurationRef -}}
{{- if not $schedulerConfiguration -}}{{ fail (print "_helpers.tpl:swh.schedulerConfiguration: key <" .configurationRef "> is mandatory in global dict .Values")}}{{- end -}}
{{- $schedulerType := get $schedulerConfiguration "cls" -}}
{{- if eq $schedulerType "remote" -}}
{{ include "swh.service.fromYaml" (dict "service" "scheduler"
                                        "configurationRef" .configurationRef
                                        "Values" .Values) }}
{{- else if eq $schedulerType "postgresql" -}}
{{ include "swh.postgresql" (dict "serviceType" "scheduler"
                                  "Values" .Values
                                  "configurationRef" .configurationRef ) }}
{{- else -}}
{{- fail (print "_helpers.tpl:swh.schedulerConfiguration: Scheduler <" $schedulerType "> not implemented") -}}
{{- end -}}
{{- end -}}

{{/*
Generate the celery configuration. This will need evolution to deal with more celery
configuration keys.
*/}}
{{- define "celery.configuration" -}}
{{- $celeryConfiguration := get .Values .configurationRef -}}
{{- $host := required (print "_helpers.tpl:celery.configuration: The <host> property is mandatory in " $celeryConfiguration)
                    (get $celeryConfiguration "host") -}}
{{- $port := required (print "_helpers.tpl:celery.configuration: The <port> property is mandatory in " $celeryConfiguration)
                    (get $celeryConfiguration "port") -}}
{{- $user := required (print "_helpers.tpl:celery.configuration: The <user> property is mandatory in " $celeryConfiguration)
                    (get $celeryConfiguration "user") -}}
{{- $pass := required (print "_helpers.tpl:celery.configuration: The <pass> property is mandatory in " $celeryConfiguration)
                    (get $celeryConfiguration "pass") -}}
celery:
  task_broker: amqp://{{ $user }}:{{ $pass }}@{{ $host }}:{{ $port }}/%2f
{{- end -}}

{{/*
Generate the deposit configuration for checkers & loaders.
*/}}
{{- define "deposit.configuration" -}}
{{- $depositConfiguration := get .Values .configurationRef -}}
{{- $host := required (print "_helpers.tpl:deposit.configuration: The <host> property is mandatory in " $depositConfiguration)
                    (get $depositConfiguration "host") -}}
{{- $user := required (print "_helpers.tpl:deposit.configuration: The <user> property is mandatory in " $depositConfiguration)
                    (get $depositConfiguration "user") -}}
{{- $pass := required (print "_helpers.tpl:deposit.configuration: The <pass> property is mandatory in " $depositConfiguration)
                    (get $depositConfiguration "pass") -}}
{{- $scheme := get $depositConfiguration "scheme" | default "https" -}}
deposit:
  url: {{ $scheme }}://{{ $host }}/1/private/
  auth:
    username: {{ $user }}
    password: {{ $pass }}
{{- end -}}

{{/* Generate the configuration for a postgresql service (e.g scheduler, storage,
   * scrubber, ...). It's also able to deal with multiple configuration (e.g. storage
   * pipeline.
   */}}
{{- define "swh.postgresql" -}}
{{- $connstring := include "swh.connstring"
                           (dict "configurationRef" .configurationRef
                                 "Values" .Values) -}}
{{- $config := (dict "cls" "postgresql" "db" $connstring) -}}
{{- if .serviceType -}}
  {{ $config = (dict .serviceType $config) }}
{{- end -}}
{{ toYaml $config }}
{{- end -}}

{{- define "django.postgresql" -}}
{{- $configuration := get .Values .configurationRef -}}
{{- $host := required (print "_helpers.tpl:django.postgresql: The <host> property is mandatory in " .configurationRef)
                    (get $configuration "host") -}}
{{- $port := required (print "_helpers.tpl:django.postgresql: The <port> property is mandatory in " .configurationRef)
                    (get $configuration "port") -}}
{{- $db := required (print "_helpers.tpl:django.postgresql: The <db> property is mandatory in " .configurationRef)
                    (get $configuration "db") -}}
{{- $user := required (print "_helpers.tpl:django.postgresql: The <user> property is mandatory in " .configurationRef)
                    (get $configuration "user") -}}
{{- $password := required (print "_helpers.tpl:django.postgresql: The <password> property is mandatory in " .configurationRef)
                    (get $configuration "pass") }}
  host: {{ $host }}
  port: {{ $port }}
  name: {{ $db }}
  user: {{ $user }}
  password: {{ $password }}
{{- end }}

{{/*
Generate the configuration for a cassandra storage
*/}}
{{- define "swh.storage.cassandra" -}}
{{- $storageConfiguration := get .Values .configurationRef -}}
{{- $cassandraSeedsRef := get $storageConfiguration "cassandraSeedsRef" -}}
{{- $cassandraSeeds := get .Values $cassandraSeedsRef -}}
{{- $keyspace := required (print "The keyspace property is mandatory in " .configurationRef)
                    (get $storageConfiguration "keyspace") -}}

{{- $config := (dict
      "cls" "cassandra"
      "hosts" $cassandraSeeds
      "keyspace" $keyspace
      "consistency_level" (get $storageConfiguration "consistencyLevel")) -}}

{{- $authProvider := get $storageConfiguration "authProvider" -}}
{{- if $authProvider -}}
  {{- $config = mustMergeOverwrite $config (dict "auth_provider" $authProvider) -}}
{{- end -}}

{{- $specificOptions := get $storageConfiguration "specificOptions" -}}
{{- if $specificOptions -}}
  {{- $config = mustMergeOverwrite $config $specificOptions -}}
{{- end -}}
{{- toYaml $config -}}
{{- end -}}

{{/*
Generate the configuration for a storage journal broker
*/}}
{{- define "swh.storage.journalWriter" -}}
{{- $journalWriterConfiguration := get .Values .configurationRef -}}
{{- $brokersRef := get $journalWriterConfiguration "brokersConfigurationRef" -}}
{{- $brokers := get .Values $brokersRef -}}
{{- $clientId := required (print "clientId property is mandatory in " .configurationRef " map") (get $journalWriterConfiguration "clientId") -}}
{{- $config := (dict
      "journal_writer" (dict
        "cls" "kafka"
        "brokers" $brokers
        "prefix" (get $journalWriterConfiguration "prefix" | default "swh.journal.objects")
        "clientId" $clientId
        "anonymize" (get $journalWriterConfiguration "anonymize" | default true)
        "producer_config" (get $journalWriterConfiguration "producerConfig" | default (dict))
        )
      ) -}}
{{- toYaml $config -}}
{{- end -}}

{{/* Generate the init keyspace container configuration if needed */}}
{{- define "swh.storage.cassandra.initKeyspaceContainer" -}}
  {{- $storageDefinition := required (print "Storage definition " .configurationRef " not found") (get .Values .configurationRef) -}}
  {{- $storageConfigurationRef := required (print "storageConfigurationRef key needed in " .configurationRef) (get $storageDefinition "storageConfigurationRef") -}}
  {{- $storageConfiguration := required (print $storageConfigurationRef " declaration not found") (get .Values $storageConfigurationRef) -}}
  {{- $storageClass := required (print "cls entry mandatory in " $storageConfigurationRef) (get $storageConfiguration "cls") -}}

  {{- if eq "cassandra" $storageClass -}}
    {{- $initKeyspace := get $storageConfiguration "initKeyspace" -}}
    {{- if $initKeyspace -}}
      {{- $cassandraSeedsRef := get $storageConfiguration "cassandraSeedsRef" -}}
      {{- $cassandraSeeds := get .Values $cassandraSeedsRef -}}
- name: init-database
  image: {{ get .Values .imagePrefixName }}:{{ get .Values (print .imagePrefixName "_version") }}
  imagePullPolicy: IfNotPresent
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

{{/* Generate the secret environment yaml config from the "configurationRef" provided.
   * This will inspect the reference provided for "secrets" key (as the function
   * "swh.secrets.environment" does). But this will also inspect the keys of that
   * configuration (the ones ending with "Ref") for "secrets" keys. If found, they will
   * also get inlined.
   */}}
{{- define "swh.secrets.environment.inline" -}}
  {{- $configuration := required (print "_helpers.tpl:swh.secrets.environment.inline: Definition <" .configurationRef "> not found") (get .Values .configurationRef) -}}
  {{ include "swh.secrets.environment" (dict "configurationRef" .configurationRef
                                             "Values" .Values) }}
  {{- $keysToCheckForSecrets := keys $configuration | sortAlpha -}}
  {{- range $keyToCheckForSecrets := $keysToCheckForSecrets }}
    {{- if and (hasSuffix "Ref" $keyToCheckForSecrets)
               (not (eq "pipelineStepsRef" $keyToCheckForSecrets)) -}}
    {{ include "swh.secrets.environment"
      (dict "configurationRef" (get $configuration $keyToCheckForSecrets)
            "Values" $.Values) }}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* Generate the secret environment yaml config if present in the config dict */}}
{{- define "swh.secrets.environment" -}}
  {{- $configuration := required (print "_helpers.tpl:swh.secrets.environment: Definition <" .configurationRef "> not found") (get .Values .configurationRef) -}}
  {{- $secrets := get $configuration "secrets" -}}
  {{- if $secrets -}}
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

{{/* Generate the storage environment config for database configuration if needed */}}
{{- define "swh.storage.secretsEnvironment" -}}
  {{- $storageDefinitionRef := required (print "_helpers.tpl:swh.storage.secretsEnvironment:Storage definition <" .configurationRef "> not found") (get .Values .configurationRef) -}}
  {{- $storageConfigurationRef := required (print "_helpers.tpl:swh.storage.secretsEnvironment:storageConfigurationRef key needed in <" $storageDefinitionRef ">") (get $storageDefinitionRef "storageConfigurationRef") -}}
{{ include "swh.secrets.environment" (dict "Values" .Values "configurationRef" $storageConfigurationRef) }}
{{- end -}}

{{/* Generate the check migration container configuration if needed */}}
{{- define "swh.checkDatabaseVersionContainer" -}}
- name: {{ .containerName | default "check-migration" }}
  image: {{ get .Values .imagePrefixName }}:{{ get .Values (print .imagePrefixName "_version") }}
  command:
  - /entrypoints/check-{{ .module }}-db-version.sh
  env:
  - name: MODULE
    value: {{ .module }}
  volumeMounts:
  - name: configuration
    mountPath: /etc/swh
  - name: database-utils
    mountPath: /entrypoints
{{- end -}}

{{/*
Generate the configuration for a journal configuration key
*/}}
{{- define "swh.journalClientConfiguration" -}}
{{- $journalConfiguration := get .Values .configurationRef -}}
{{- $brokersRef := required (print "brokersConfigurationRef is mandatory in <" $journalConfiguration "> map" ) (get $journalConfiguration "brokersConfigurationRef") -}}
{{- $brokers := required (print "<" $brokersRef "> is mandatory in the global values <" .Values "> map") (get .Values $brokersRef) -}}
{{- $configuration := deepCopy $journalConfiguration }}
{{- $overrides := .overrides | default dict }}
{{- $configuration := mustMergeOverwrite $configuration $overrides -}}
{{- $_ := unset $configuration "secrets" -}}
{{- $_ := unset $configuration "brokersConfigurationRef" -}}
{{- $_ := required (print "group_id property is mandatory in <" .configurationRef "> map") (get $configuration "group_id") -}}
{{ .serviceType | default "journal" }}:
  brokers:
{{ toYaml $brokers | indent 4 }}
{{ toYaml $configuration | indent 2 }}
{{- end -}}

{{/*
Generate the configuration for a remote service
*/}}
{{- define "swh.service.fromYaml" -}}
{{- $configuration := deepCopy (get .Values .configurationRef) -}}
{{- $_ := unset $configuration "secrets" -}}
{{ .service }}:
{{ toYaml $configuration | indent 2 }}
{{- end -}}

{{/*
Generate the configuration for a journal_writer configuration entry
*/}}
{{- define "swh.journal.configuration" -}}
{{- $configuration := deepCopy (get .Values .configurationRef) -}}
{{- $kafkaBrokers := get .Values (get $configuration "brokersConfigurationRef") -}}
{{- $_ := unset $configuration "brokersConfigurationRef" -}}
{{ .serviceType }}:
  {{- toYaml $configuration | nindent 2 }}
  brokers:
  {{- range $broker := $kafkaBrokers }}
  - {{ $broker }}
  {{- end}}
{{- end -}}

{{/*
Generate the configuration for search
*/}}
{{- define "swh.search.configuration" -}}
{{- $configuration := deepCopy (get .Values .configurationRef) -}}
{{- $elasticsearchInstances := get .Values (get $configuration "elasticsearchInstancesRef") -}}
{{- $_ := unset $configuration "elasticsearchInstancesRef" -}}
{{ .serviceType }}:
  {{ toYaml $configuration | nindent 2 }}
  hosts:
  {{ toYaml $elasticsearchInstances | nindent 4 }}
{{- end -}}

{{/*
Generate the resolver configuration
*/}}
{{- define "swh.dns.configuration" -}}
{{- $configuration := deepCopy (get .Values .configurationRef) -}}
{{- if $configuration.policy }}
dnsPolicy: "{{ $configuration.policy }}"
{{- end }}
dnsConfig:
{{- if $configuration.ndots }}
  options:
    - name: ndots
      value: "{{ $configuration.ndots }}"
{{- end }}
{{- if $configuration.overrideSearch }}
  searches:
    - cluster.local
    - svc.cluster.local
    - {{ .Values.namespace }}.svc.cluster.local
{{- range $extraSearch := get $configuration "extraSearch" | default (list) }}
    - {{ $extraSearch }}
{{- end }}
{{- end }}
{{- if $configuration.nameservers }}
  nameservers:
  {{- range $nameserver := $configuration.nameservers }}
    - {{ $nameserver }}
  {{- end }}
{{- end }}
{{- end -}}
