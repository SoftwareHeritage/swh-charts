# -*- yaml -*-

{{/*
Create a Kind Ingress for service .serviceType
*/}}
{{- define "swh.ingress" -}}
{{- $serviceType := .serviceType }}
{{- $configuration := .configuration }}
{{- $hosts := $configuration.hosts }}
{{- $defaultWhitelistSourceRangeRef := $configuration.ingress.whitelistSourceRangeRef | default "inexistant" -}}
{{- $defaultWhitelistSourceRange := get .Values $defaultWhitelistSourceRangeRef | default list -}}
{{- range $endpoint_definition, $endpoint_config := $configuration.ingress.endpoints -}}
{{- $extraWhitelistSourceRange := get $endpoint_config "extraWhitelistSourceRange" | default list -}}
{{- $whitelistSourceRange := join "," (concat $defaultWhitelistSourceRange $extraWhitelistSourceRange | uniq | sortAlpha) | default "" -}}
{{- $paths := get $endpoint_config "paths" -}}
{{- $authenticated := get $endpoint_config "authentication" -}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: {{ $.Values.namespace }}
  name: {{ $serviceType }}-ingress-{{ $endpoint_definition }}
  annotations:
  {{- if $whitelistSourceRange }}
    nginx.ingress.kubernetes.io/whitelist-source-range: {{ $whitelistSourceRange }}
  {{- end }}
  {{- if $configuration.ingress.extraAnnotations }}
  {{ toYaml $configuration.ingress.extraAnnotations | nindent 4 }}
  {{ end }}
  {{- if $authenticated }}
    # type of authentication
    nginx.ingress.kubernetes.io/auth-type: basic
    # an htpasswd file in the key auth within the secret
    nginx.ingress.kubernetes.io/auth-secret-type: auth-file
    # name of the secret that contains the user/password definitions
    nginx.ingress.kubernetes.io/auth-secret: {{ $authenticated }}
    # message to display with an appropriate context why the authentication is required
    nginx.ingress.kubernetes.io/auth-realm: 'Authentication Required'
  {{- end }}

spec:
  {{- if $configuration.ingress.className }}
  ingressClassName: {{ $configuration.ingress.className }}
  {{- end }}
  rules:
  {{- range $host := $hosts }}
  - host: {{ $host }}
    http:
      paths:
      {{- range $path_config := $paths }}
      {{- $port := get $path_config "port" | default $configuration.port }}
      - path: {{ get $path_config "path" }}
        pathType: Prefix
        backend:
          service:
            name: {{ $serviceType }}
            port:
              number: {{ $port }}
      {{ end }}
  {{- end }}
  {{- if and $configuration.ingress.tlsEnabled $configuration.ingress.secretName }}
  tls:
  - hosts:
    {{- range $host := $hosts }}
    - {{ $host }}
    {{- end }}
    secretName: {{ $configuration.ingress.secretName }}
  {{- end }}
{{ end }}
{{ end }}

