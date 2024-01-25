{{/*
Create a Kind service for .serviceType
*/}}
{{- define "swh.service" -}}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .serviceType }}
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .serviceType }}
spec:
  type: ClusterIP
  selector:
    app: {{ .serviceType }}
  ports:
    - port: {{ .configuration.port }}
      targetPort: {{ .configuration.port }}
      name: rpc
    {{ if .configuration.extraPorts }}
    {{- range $label_port, $port := .configuration.extraPorts }}
    - port: {{ $port }}
      targetPort: {{ $port }}
      name: {{ $label_port }}
    {{ end }}
    {{ end }}
{{ end }}
