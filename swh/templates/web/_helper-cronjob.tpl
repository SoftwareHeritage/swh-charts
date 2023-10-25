# -*- yaml -*-

{{/*
Create a Kind CronJob for service .serviceType
*/}}
{{- define "swh.web.cronjob" -}}
{{- with .configuration -}}
{{- $log_level := .logLevel -}}
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ $.serviceType }}-cronjob
spec:
  schedule: {{ .cron | quote}}
  jobTemplate:
    spec:
      {{- if .concurrencyPolicy }}
      concurrencyPolicy: {{ .concurrencyPolicy }}
      {{- end }}
      template:
        spec:
          {{- if and $.Values.podPriority.enabled .priorityClassName }}
          priorityClassName: {{ $.Values.namespace }}-{{ .priorityClassName }}
          {{ end }}
          initContainers:
            - name: prepare-configuration
              image: debian:bullseye
              imagePullPolicy: IfNotPresent
              command:
              - /bin/bash
              args:
              - -c
              - eval echo "\"$(</etc/swh/configuration-template/config.yml.template)\"" > /etc/swh/config.yml
              env:
                {{- if $.Values.web.databaseConfigurationRef }}
                {{- include "swh.secrets.environment" (dict "Values" $.Values
                                                            "configurationRef" $.Values.web.databaseConfigurationRef) | nindent 16 -}}
                {{ end }}
                {{- if $.Values.web.djangoConfigurationRef }}
                {{- include "swh.secrets.environment" (dict "Values" $.Values
                                                            "configurationRef" $.Values.web.djangoConfigurationRef) | nindent 16 }}
                {{ end }}
                {{- if $.Values.web.depositConfigurationRef -}}
                {{- include "swh.secrets.environment" (dict "Values" $.Values
                                                            "configurationRef" $.Values.web.depositConfigurationRef) | nindent 16 }}
                {{ end }}
                {{- if $.Values.web.giveConfigurationRef -}}
                {{- include "swh.secrets.environment" (dict "Values" $.Values
                                                            "configurationRef" $.Values.web.giveConfigurationRef) | nindent 16 }}
                {{ end }}
                {{- if $.Values.web.sentry.enabled }}
                - name: SWH_SENTRY_DSN
                  valueFrom:
                    secretKeyRef:
                      name: {{ $.Values.web.sentry.secretKeyRef }}
                      key: {{ $.Values.web.sentry.secretKeyName }}
                      # 'name' secret should exist & include key
                      # if the setting doesn't exist, sentry pushes will be disabled
                      optional: true
                {{ end }}
              volumeMounts:
              - name: configuration
                mountPath: /etc/swh
              - name: configuration-template
                mountPath: /etc/swh/configuration-template
          containers:
            - name: {{ $.serviceType }}
              resources:
                requests:
                  memory: {{ .requestedMemory | default "512Mi" }}
                  cpu: {{ .requestedCpu | default "500m" }}
                {{- if or .limitedMemory .limitedCpu }}
                limits:
                {{- if .limitedMemory }}
                  memory: {{ .limitedMemory }}
                {{- end }}
                {{- if .limitedCpu }}
                  cpu: {{ .limitedCpu }}
                {{- end }}
                {{ end }}
              image: {{ $.Values.swh_web_image }}:{{ $.Values.swh_web_image_version }}
              command:
              - /opt/swh/entrypoint.sh
              args:
              {{- range $cmd := $.command }}
              - {{ $cmd }}
              {{- end }}
              env:
                - name: STATSD_HOST
                  value: {{ $.Values.statsdExternalHost | default "prometheus-statsd-exporter" }}
                - name: STATSD_PORT
                  value: {{ $.Values.statsdPort | default "9125" | quote }}
                - name: SWH_CONFIG_FILENAME
                  value: /etc/swh/config.yml
                - name: LOG_LEVEL
                  value: {{ $log_level | default "INFO" }}
                {{- if hasKey $.configuration "configurationRef" -}}
                {{- include "swh.secrets.environment" (dict "Values" $.Values
                                                            "configurationRef" $.configuration.configurationRef) | nindent 16 }}
                {{ end }}
              {{- if $.Values.web.sentry.enabled }}
                - name: SWH_SENTRY_ENVIRONMENT
                  value: {{ $.Values.sentry.environment }}
                - name: SWH_MAIN_PACKAGE
                  value: swh.web
                - name: SWH_SENTRY_DSN
                  valueFrom:
                    secretKeyRef:
                      name: {{ $.Values.web.sentry.secretKeyRef }}
                      key: {{ $.Values.web.sentry.secretKeyName }}
                      # if the setting doesn't exist, sentry issue pushes will be disabled
                      optional: false
                - name: SWH_SENTRY_DISABLE_LOGGING_EVENTS
                  value: "true"
              {{- end }}
              imagePullPolicy: IfNotPresent
              volumeMounts:
              - name: configuration
                mountPath: /etc/swh
          volumes:
          - name: configuration
            emptyDir: {}
          - name: configuration-template
            configMap:
              name: web-configuration-template
              items:
              - key: "config.yml.template"
                path: "config.yml.template"
          restartPolicy: OnFailure

{{ end }}
{{- end -}}
