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
spec:
  type: ClusterIP
  selector:
    app: {{ .serviceType }}
  ports:
    - port: {{ .configuration.port }}
      targetPort: {{ .configuration.port }}
      name: rpc
{{ end }}
