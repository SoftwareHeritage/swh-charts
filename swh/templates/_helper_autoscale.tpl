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
