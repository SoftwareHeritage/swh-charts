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
{{- else if eq $storageType "memory" -}}
  {{- $storageConfig = mustMergeOverwrite $storageConfig (dict "cls" "memory") -}}
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
  {{- $journalWriterConfig := include "swh.journalWriterConfiguration"
                                      (dict "service_type" "journal_writer"
                                            "configurationRef" $journalWriterConfigurationRef
                                            "Values" .Values) | fromYaml -}}
  {{- $storageConfig = mustMergeOverwrite $storageConfig $journalWriterConfig -}}
{{- end -}}

{{- $pipelineStepsRef := get $storageConfiguration "pipelineStepsRef" -}}
{{- if $pipelineStepsRef -}}
  {{- $pipelineSteps := include "swh.storage.parsePipelineSteps" (dict "Values" .Values "pipelineStepsRef" $pipelineStepsRef) | fromYamlArray -}}
  {{- $pipelineSteps = mustAppend $pipelineSteps $storageConfig -}}
  {{- $storageConfig = (dict "cls" "pipeline" "steps" $pipelineSteps) -}}
{{- end -}}
{{- dict (get . "service" | default "storage") $storageConfig | toYaml -}}
{{- end -}}

{{/* Parse a storage pipeline steps definition out of the .pipelineStepsRef key */}}
{{- define "swh.storage.parsePipelineSteps" -}}
{{- if not (hasKey .Values .pipelineStepsRef) -}}
  {{- fail (print "_helpers.tpl:swh.storage.parsePipelineSteps: No pipeline steps configuraton found:" .pipelineStepsRef) -}}
{{- end -}}
{{- $Values := .Values -}}
{{- $pipelineSteps := (list) -}}
{{- range $pipelineStep := get $Values .pipelineStepsRef -}}
  {{- if not (hasKey $pipelineStep "cls") -}}
    {{- fail (print "_helpers.tpl:swh.storage.parsePipelineSteps: Pipeline step in " .pipelineStepsRef " is missing mandatory cls key") -}}
  {{- end -}}
  {{- if (or (eq $pipelineStep.cls "masking") (eq $pipelineStep.cls "blocking")) -}}
    {{- if not (hasKey $pipelineStep "postgresqlConfigurationRef") -}}
      {{- fail (print "_helpers.tpl:swh.storage.parsePipelineSteps: Masking pipeline step in " .pipelineStepsRef " is missing mandatory postgresqlConfigurationRef key") -}}
    {{- end -}}
    {{- $cls := $pipelineStep.cls -}}
    {{- $keyDb := print $cls "_db" -}}
    {{- $queryDb := include "swh.connstring"
                            (dict "configurationRef" $pipelineStep.postgresqlConfigurationRef
                                  "Values" $Values) -}}

    {{- $pipelineSteps = mustAppend $pipelineSteps (dict "cls" $cls $keyDb $queryDb) -}}
  {{- else -}}
    {{- $pipelineSteps = mustAppend $pipelineSteps $pipelineStep -}}
  {{- end -}}
{{- end -}}
{{ $pipelineSteps | toYaml }}
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
Generate the configuration for a journal writer
*/}}
{{- define "swh.journalWriterConfiguration" -}}
{{- $journalWriterConfiguration := get .Values .configurationRef -}}
{{- $brokersRef := get $journalWriterConfiguration "brokersConfigurationRef" -}}
{{- $brokers := get .Values $brokersRef -}}
{{- $clientId := required (print "clientId property is mandatory in " .configurationRef " map") (get $journalWriterConfiguration "clientId") -}}
{{- $config := (dict
      (get . "service" | default "journal_writer") (dict
        "cls" "kafka"
        "brokers" $brokers
        "prefix" (get $journalWriterConfiguration "prefix" | default "swh.journal.objects")
        "client_id" $clientId
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

{{/* Merge .newSecrets into .collectedSecrets */}}
{{- define "swh.secrets.mergeDicts" -}}
{{- range $secretName, $secretsConfig := .newSecrets -}}
  {{/* Check that the secret is not clashing */}}
  {{- $collected := get $.collectedSecrets $secretName -}}
  {{- if (and $collected (not (deepEqual $collected $secretsConfig))) -}}
    {{- fail (print "_helpers.tpl:swh.secrets.mergeDicts: "
                  "Duplicate secret <" $secretName ">, with incompatible values <"
                  $collected "> and <" $secretsConfig "> at path " $.path) -}}
  {{- end -}}
  {{- $_ := set $.collectedSecrets $secretName $secretsConfig -}}
{{- end -}}
{{- end -}}

{{/* Extract secrets from a deployment config; This traverses any reference, recursively. */}}
{{- define "swh.secrets.dictFromDeploymentConfig" -}}
{{/* Check mandatory keys */}}
{{- if (not (hasKey . "deploymentConfig")) -}}
  {{- fail "_helpers.tpl:swh.secrets.dictFromDeploymentConfig missing deploymentConfig" -}}
{{- end -}}
{{- if (not (hasKey . "Values")) -}}
  {{- fail "_helpers.tpl:swh.secrets.dictFromDeploymentConfig missing Values" -}}
{{- end -}}
{{/* To access .Values from nested ranges */}}
{{- $Values := .Values -}}
{{/* Path inside the data structure */}}
{{- $path := default "deploymentConfig" .path -}}

{{- $collectedSecrets := dict -}}

{{- range $key, $value := .deploymentConfig -}}
  {{- if (eq $key "secrets") -}}
    {{/* This config has secrets, pull them directly */}}
    {{- include "swh.secrets.mergeDicts" (dict "collectedSecrets" $collectedSecrets
                                               "newSecrets" $value
                                               "path" $path) -}}
  {{- else if (kindIs "map" $value) -}}
    {{/* the value is a mapping, we should recurse into it to find more secrets */}}
    {{- $nestedPath := (print $path "." $key) -}}
    {{- $newSecrets := include "swh.secrets.dictFromDeploymentConfig" (dict "Values" $Values
                                                                            "deploymentConfig" $value
                                                                            "path" $nestedPath) | fromYaml -}}
    {{- $_ := include "swh.secrets.mergeDicts" (dict "collectedSecrets" $collectedSecrets
                                                     "newSecrets" $newSecrets
                                                     "path" $nestedPath) -}}
  {{- else if (and (ne "secretKeyRef" $key) (hasSuffix "Ref" $key) (kindIs "string" $value)) -}}
    {{/* This is an indirect config, we need to pull it from $Values then recurse */}}
    {{- $referencedConfig := get $Values $value | required (print
          "_helpers.tpl:swh.secrets.dictFromDeploymentConfig: "
          "missing definition for <" $value "> referenced as a <" $key "> ") -}}
    {{/* recurse into the referencedConfig */}}
    {{- if (kindIs "map" $referencedConfig) -}}
      {{/* referencedConfig is a map, we can just pass it to ourselves */}}
      {{- $nestedPath := (print $path "." $key "> ." $value) -}}
      {{- $newSecrets := include "swh.secrets.dictFromDeploymentConfig" (dict "Values" $Values
                                                                              "deploymentConfig" $referencedConfig
                                                                              "path" $nestedPath) | fromYaml -}}
      {{- $_ := include "swh.secrets.mergeDicts" (dict "collectedSecrets" $collectedSecrets
                                                       "newSecrets" $newSecrets
                                                       "path" $nestedPath) -}}
    {{- else if (kindIs "slice" $referencedConfig) -}}
      {{/* referencedConfig is a list-like object, iterate over it */}}
      {{- range $referencedItem := $referencedConfig -}}
        {{- $nestedPath := (print $path "." $key "> ." $value "[]") -}}
        {{- if (kindIs "map" $referencedItem) -}}
          {{/* referencedItem is a map, we can just pass it to ourselves */}}
          {{- $newSecrets := include "swh.secrets.dictFromDeploymentConfig" (dict "Values" $Values
                                                                                  "deploymentConfig" $referencedItem
                                                                                  "path" $nestedPath) | fromYaml -}}
          {{- $_ := include "swh.secrets.mergeDicts" (dict "collectedSecrets" $collectedSecrets
                                                           "newSecrets" $newSecrets
                                                           "path" $nestedPath) -}}
        {{- else -}}
          {{/* $referencedItem has unsupported type, ignore it */}}
        {{- end -}}
      {{- end -}}
    {{- else -}}
      {{/* $referencedConfig has unsupported type, ignore it */}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if $collectedSecrets -}}
{{ $collectedSecrets | toYaml }}
{{- end -}}
{{- end -}}

{{/* Convert a secrets dict into an environment variable list */}}
{{- define "swh.secrets.envFromDict" -}}
{{- $envList := list -}}
{{- range $secretName, $secretsConfig := .secrets -}}
  {{- if $secretsConfig -}}
    {{- $envList = mustAppend $envList (dict
      "name" $secretName
      "valueFrom" (dict
        "secretKeyRef" (dict
          "name" (get $secretsConfig "secretKeyRef")
          "key" (get $secretsConfig "secretKeyName")
          "optional" false))) -}}
  {{- else -}}
    {{ fail (print "Definition for collected secret <" $secretName "> is empty"
             " when getting secrets for deployment configuration <" $.args.deploymentConfig ">") }}
  {{- end -}}
{{- end -}}
{{ $envList | toYaml }}
{{- end -}}

{{/* Collect secrets from a deployment config, and generate an environment variable list */}}
{{- define "swh.secrets.envFromDeploymentConfig" -}}
{{- $secretsYaml := include "swh.secrets.dictFromDeploymentConfig" . -}}
{{- if $secretsYaml -}}
  {{- include "swh.secrets.envFromDict" (dict "args" . "secrets" (fromYaml $secretsYaml)) -}}
{{- end -}}
{{- end -}}

{{/* Generate the check migration container configuration if needed */}}
{{- define "swh.checkDatabaseVersionContainer" -}}
{{- $image_version := get . "imageVersion" | default ( get .Values (print .imagePrefixName "_version") ) |
        required (print .imagePrefixName "_version is mandatory in values.yaml ") -}}
- name: {{ .containerName | default "check-migration" }}
  image: {{ get .Values .imagePrefixName }}:{{ $image_version }}
  command:
  - /entrypoints/check-backend-version.sh
  env:
  - name: MODULE
    value: {{ .module }}
  - name: MODULE_CONFIG_KEY
    value: {{ .moduleConfigKey | default "" }}
  - name: SWH_CONFIG_FILENAME
    value: /etc/swh/config.yml
  volumeMounts:
  - name: configuration
    mountPath: /etc/swh
  - name: database-utils
    mountPath: /entrypoints
{{- end -}}

{{/* Generate the initialize backend container configuration if needed */}}
{{- define "swh.initializeBackend" -}}
{{- $image_version := get . "imageVersion" | default ( get .Values (print .imagePrefixName "_version") ) |
        required (print .imagePrefixName "_version is mandatory in values.yaml ") -}}
- name: {{ .containerName | default "initialize-backend" }}
  image: {{ get .Values .imagePrefixName }}:{{ $image_version }}
  command:
  - /entrypoints/initialize-backend.sh
  env:
  - name: MODULE
    value: {{ .module }}
  - name: MODULE_CONFIG_KEY
    value: {{ .moduleConfigKey | default "" }}
  - name: SWH_CONFIG_FILENAME
    value: /etc/swh/config.yml
  - name: SWH_PGDATABASE
    value: {{ .config.database }}
  - name: SWH_PGPASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ .config.adminSecret }}
        key: password
  - name: SWH_PGHOST
    valueFrom:
      secretKeyRef:
        name: {{ .config.adminSecret }}
        key: host
  volumeMounts:
  - name: configuration
    mountPath: /etc/swh
  - name: database-utils
    mountPath: /entrypoints
{{- end -}}

{{/* Generate the initialize backend container configuration if needed */}}
{{- define "swh.migrateBackend" -}}
{{- $image_version := get . "imageVersion" | default ( get .Values (print .imagePrefixName "_version") ) |
        required (print .imagePrefixName "_version is mandatory in values.yaml ") -}}
{{- $entrypoint := eq .module "storage" | ternary "migrate-storage-db-version.sh" "migrate-db-version.sh" -}}
- name: {{ .containerName | default "migrate-backend" }}
  image: {{ get .Values .imagePrefixName }}:{{ $image_version }}
  command:
  - /entrypoints/migrate-backend.sh
  env:
  - name: MODULE
    value: {{ .module }}
  - name: MODULE_CONFIG_KEY
    value: {{ .moduleConfigKey | default "" }}
  - name: SWH_CONFIG_FILENAME
    value: /etc/swh/config.yml
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

{{/*
Debug variable during chart development.
To use like this:

template "swh.var_dump" $variable

*/}}
{{- define "swh.var_dump" -}}
{{- . | mustToPrettyJson | printf "####\nJSON output:\n%s\n####" | fail }}
{{- end -}}

