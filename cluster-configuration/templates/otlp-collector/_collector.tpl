# -*- yaml -*-
# Collector configuration to include in the "helm" > "values" keys
# in the argocd application defined in application.yaml
{{ if .Values.otlpCollector.enabled -}}
{{- $environment := get .Values "environment" }}
{{- $logs_swh := .Values.otlpCollector.indexes.swh | default "swh-logs" -}}
{{- $logs_system := .Values.otlpCollector.indexes.system | default "system-logs" -}}
{{- $activate_debug := .Values.otlpCollector.debug -}}
---
mode: daemonset
presets:
  # Configures the collector to collect logs.
  # Adds the filelog receiver to the logs pipeline
  # and adds the necessary volumes and volume mounts.
  # Best used with mode = daemonset.
  logsCollection:
    # Not enabled as this configures too much. Only the necessary is opened below
    enabled: false
  # Configures the Kubernetes Processor to add Kubernetes metadata.
  # Adds the k8sattributes processor to all the pipelines
  # and adds the necessary rules to ClusteRole.
  # Best used with mode = daemonset.
  kubernetesAttributes:
    enabled: true
  # Configures the collector to collect host metrics.
  # Adds the hostmetrics receiver to the metrics pipeline
  # and adds the necessary volumes and volume mounts.
  # Best used with mode = daemonset.
  hostMetrics:
    # Not enabled as this configures too much. Only the necessary is opened below
    enabled: false

extraEnvs:
- name: KUBE_NODE_NAME
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: spec.nodeName

extraVolumes:
- name: varlogpods
  hostPath:
    path: /var/log/pods
    type: Directory

extraVolumeMounts:
- mountPath: /var/log/pods
  name: varlogpods

resources:
  requests:
    cpu: {{ .Values.otlpCollector.resources.cpu | default "256m" }}
    memory: {{ .Values.otlpCollector.resources.memory | default "2Gi" }}

# The pod monitor by default scrapes the metrics port.
# The metrics port needs to be enabled as well.
podMonitor:
  enabled: true

ports:
  # The metrics port is disabled by default. So we need to enable the port
  # in order to use the PodMonitor (PodMonitor.enabled)
  metrics:
    enabled: true

config:
  exporters:
    {{- if $activate_debug }}
    logging/debug:
      loglevel: debug
    {{- end }}
    elasticsearch/swh-log:
      endpoints:
        {{- toYaml .Values.otlpCollector.endpoints | nindent 8 }}
      logs_index: {{ print $logs_swh "-" }}
      logs_dynamic_index:
        enabled: true
      # Contrary to documentation, this does not work. It fails to parse the configmap
      # error with it enabled
      # retry_on_failure:
      #   enabled: true
      timeout: {{ .Values.otlpCollector.resources.timeout | default "10s" }}
    elasticsearch/system-log:
      # can be replaced by using the env variable ELASTICSEARCH_URL
      endpoints:
        {{- toYaml .Values.otlpCollector.endpoints | nindent 8 }}
      logs_index: {{ print $logs_system "-" }}
      logs_dynamic_index:
        enabled: true
      timeout: {{ .Values.otlpCollector.resources.timeout | default "10s" }}

  extensions:
    # with port-forward, allows to display the pipeline status to see what's been
    # deployed
    zpages:
      endpoint: "0.0.0.0:8889"
    # The health_check extension is mandatory for this chart. Without the health_check
    # extension the collector will fail the readiness and liveliness probes. The
    # health_check extension can be modified, but should never be removed.
    health_check: {}

  receivers:
    filelog/system:
      include:
        - /var/log/pods/*/*/*.log
      exclude:
        # Exclude 'swh*' namespaced logs
        - /var/log/pods/swh*_*/*/*.log
      start_at: beginning
      include_file_path: true
      include_file_name: false
      multiline:
        # as of now, starts as a date pattern (see parser-containerd below)
        line_start_pattern: '^[^ Z]+Z'
      operators:
      # Find out which log format is used to route it to proper parsers
      # Extract metadata from file path
      - id: extract_metadata_from_filepath
        type: regex_parser
        regex: '^.*\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[a-f0-9\-]{32,36})\/(?P<container_name>[^\._]+)\/(?P<run_id>\d+)\.log$'
        parse_from: attributes["log.file.path"]
        parse_to: resource
      # Parse CRI-Containerd format
      - id: parser-containerd
        type: regex_parser
        regex: '^(?P<time>[^ ^Z]+Z) (?P<stream>stdout|stderr)( (?P<logtag>[^ ]*) (?P<message>.*)|.*)$'
        timestamp:
          parse_from: attributes.time
          layout: '%Y-%m-%dT%H:%M:%S.%LZ'
      # e.g. redis logs are "mostly" json, but no the ts entry is a timestamp that's
      # not adequately parsed. Type:"mapper_parsing_exception", Reason:"failed to
      # parse field [Attributes.ts] of type [date] in document...
      # - id: parser-json-message
      #   type: json_parser
      #   parse_from: attributes['message']
      #   parse_to: attributes
      #   if: attributes.message matches "^\\{"

    filelog/swh:
      include:
        # Only keep 'swh*' namespaces
        - /var/log/pods/swh*_*/*/*.log
      start_at: beginning
      include_file_path: true
      include_file_name: false
      multiline:
        # as of now, starts as a date pattern (see parser-containerd below)
        line_start_pattern: '^[^ Z]+Z'
      operators:
      # Find out which log format is used to route it to proper parsers
      # Extract metadata from file path
      - id: extract_metadata_from_filepath
        type: regex_parser
        regex: '^.*\/(?P<namespace>[^_]+)_(?P<pod_name>[^_]+)_(?P<uid>[a-f0-9\-]{36})\/(?P<container_name>[^\._]+)\/(?P<run_id>\d+)\.log$'
        parse_from: attributes["log.file.path"]
        parse_to: resource
      # Parse CRI-Containerd format
      - id: parser-containerd
        type: regex_parser
        regex: '^(?P<time>[^ ^Z]+Z) (?P<stream>stdout|stderr)( (?P<logtag>[^ ]*) (?P<message>.*)|.*)$'
        timestamp:
          parse_from: attributes.time
          layout: '%Y-%m-%dT%H:%M:%S.%LZ'
      # then parse the json formatted message if any
      - id: parser-json-message
        type: json_parser
        parse_from: attributes['message']
        parse_to: attributes
        if: attributes.stream == 'stdout' && attributes.message matches "^\\{"
      # Those were an attempt to inline the json further but entries 'data.kwargs' and
      # 'return_value' are python dict and not json so we cannot parse them.
      # - id: parser-json-kwargs
      #   type: json_parser
      #   parse_from: attributes.data.kwargs
      #   parse_to: attributes
      #   if: attributes.stream == 'stdout' && attributes.data?.kwargs != nil
      # - id: parser-json-return-value
      #   type: json_parser
      #   parse_from: attributes.return_value
      #   parse_to: attributes
      #   if: attributes.stream == 'stdout' && attributes?.return_value != nil
      # This deals with basic key=value logs (it's not able to deal with "multi"
      # values those like key="this is a value" though, so prometheus, memcached logs
      # are not parsed so far)
      # - id: parse-key-value-message
      #   type: key_value_parser
      #   delimiter: "="
      #   pair_delimiter: " "
      #   parse_from: attributes['message']
      #   parse_to: attributes
      #   if: attributes.message matches "^ts="

  processors:
    resource:
      attributes:
        - key: k8s.pod.name
          from_attribute: pod_name
          action: upsert
    k8sattributes:
      filter:
        node_from_env_var: KUBE_NODE_NAME
      passthrough: false
      extract:
        metadata:
          # from https://opentelemetry.io/docs/reference/specification/resource/semantic_conventions/k8s/
          - k8s.pod.name
          - k8s.pod.uid
          - k8s.deployment.name
          - k8s.namespace.name
          - k8s.node.name
          - k8s.pod.start_time
          - k8s.daemonset.name
          - k8s.job.name
          - k8s.cronjob.name
          # Desired properties (but not working for now)
          # 2023/04/26 08:54:58 collector server run finished with error: failed to
          # build pipelines: failed to create "k8sattributes" processor, in pipeline
          # "logs/system": "k8s.cluster.name" (or "deployment.environment" )
          # - k8s.cluster.name
          # - deployment.environment
      pod_association:
        - sources:
          - from: resource_attribute
            name: k8s.pod.name
        - sources:
          - from: connection
            name: k8s.pod.ip
        - sources:
          - from: resource_attribute
            name: k8s.pod.ip
    batch:
      # for debug
      {{- if $activate_debug }}
      send_batch_size: 1
      {{- else }}
      send_batch_size: {{ .Values.otlpCollector.resources.batch | default "10" }}
      {{- end }}
    # No longer working with version > 0.52
    # memory_limiter: null
    attributes/insert:
      actions:
      - key: environment
        value: {{ $environment }}
        action: insert
      - key: cluster
        value: {{ .Values.clusterName }}
        action: insert
      # for dynamic indexation, the environment is the index prefix
      - key: index.prefix
        value: {{ ( print $environment "-" ) }}
        action: insert
    attributes/regexp_insert:
      actions:
      # First extract the suffix (we can't name it as we need to, with ".",
      # otherwise, it's complaining about regexp not being ok)
      - key: "asctime"
        pattern: ^(?P<suffix>[\d\-]{10}).*
        action: extract
      # Then we need to convert to a string as it's converted as a date (and we don't have a saying in this)
      - key: suffix
        action: convert
        converted_type: string
      # Finally we move where we need to
      - key: elasticsearch.index.suffix
        from_attribute: suffix
        action: upsert
    attributes/clean-records:
      actions:
      - key: time
        action: delete
      - key: suffix
        action: delete
      - key: logtag
        action: delete
      - key: log
        action: delete
      - key: log.keyword
        action: delete
      - key: log.file.path
        action: delete
      - key: log.value
        action: delete

  service:
    telemetry:
      metrics:
        address: ${MY_POD_IP}:8888
      {{- if $activate_debug }}
      logs:
        level: "debug"
      {{- end }}
    extensions:
      - health_check
      - memory_ballast

    pipelines:
      logs/system:
        receivers:
          - filelog/system
        processors:
          - batch
          - resource
          - k8sattributes
          - attributes/insert
          - attributes/regexp_insert
          - attributes/clean-records
        exporters:
          - elasticsearch/system-log
      logs/swh:
        receivers:
          - filelog/swh
        processors:
          - batch
          - resource
          - k8sattributes
          - attributes/insert
          - attributes/regexp_insert
          - attributes/clean-records
        exporters:
          - elasticsearch/swh-log
      # inhibit pipelines
      logs: null
      metrics: null
      traces: null
{{- end -}}
