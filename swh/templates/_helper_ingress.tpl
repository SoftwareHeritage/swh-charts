# -*- yaml -*-

{{/*
Create a Kind Ingress for service .serviceType
*/}}
{{- define "swh.ingress" -}}
{{- $serviceType := .serviceType -}}
{{- $configuration := .configuration -}}
{{- $hosts := pluck "hosts" $configuration.ingress $configuration | first -}}
{{- $defaultWhitelistSourceRangeRef := $configuration.ingress.whitelistSourceRangeRef | default "inexistant" -}}
{{- $defaultWhitelistSourceRange := get .Values $defaultWhitelistSourceRangeRef | default list -}}
{{- $nameLabel := hasKey . "extraNameLabel" | ternary (print "ingress-" .extraNameLabel) "ingress" -}}
{{- range $endpoint_definition, $endpoint_config := $configuration.ingress.endpoints -}}
{{- $extraWhitelistSourceRange := get $endpoint_config "extraWhitelistSourceRange" | default list -}}
{{- $whitelistSourceRange := join "," (concat $defaultWhitelistSourceRange $extraWhitelistSourceRange | uniq | sortAlpha) | default "" -}}
{{- $paths := get $endpoint_config "paths" -}}

{{- $annotations := (dict) -}}

{{- if or (not (hasKey $configuration.ingress "useEndpointsAsUpstream")) (eq $configuration.ingress.useEndpointsAsUpstream false) -}}
{{/* undocumented swh's ingress option to configure the upstreams to use the service ip.
        By default, ips of endpoints are directly used by nginx to load balance the requests, but it's
        ineffective for non-"idempotent" requests (POST).
        So by default, the ingresses are configured to use the service as upstream.
        https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#service-upstream
        Using the default behavior (endpoints ips) should not be necessary according to the swh services architecture,
        but allowing it just in case
*/}}
  {{- $annotations = mustMergeOverwrite $annotations (dict "nginx.ingress.kubernetes.io/service-upstream" "true") -}}
{{- end }}

{{- if $whitelistSourceRange -}}
  {{- $annotations = mustMergeOverwrite $annotations (dict "nginx.ingress.kubernetes.io/whitelist-source-range" $whitelistSourceRange ) -}}
{{- end -}}
{{- if and (or $configuration.ingress.tlsEnabled $endpoint_config.tlsEnabled) $configuration.ingress.tlsExtraAnnotations -}}
  {{- $annotations = mustMergeOverwrite $annotations $configuration.ingress.tlsExtraAnnotations }}
{{- end -}}
{{- if get $endpoint_config "authentication" -}}
  {{/* type of authentication */}}
  {{- $annotations = mustMergeOverwrite $annotations (dict "nginx.ingress.kubernetes.io/auth-type" "basic") -}}
  {{/* an htpasswd file in the key auth within the secret */}}
  {{- $annotations = mustMergeOverwrite $annotations (dict "nginx.ingress.kubernetes.io/auth-secret-type" "auth-file") -}}
  {{/* name of the secret that contains the user/password definitions */}}
  {{- $annotations = mustMergeOverwrite $annotations (dict "nginx.ingress.kubernetes.io/auth-secret" $endpoint_config.authentication) -}}
  {{/* message to display with an appropriate context why the authentication is required */}}
  {{- $annotations = mustMergeOverwrite $annotations (dict "nginx.ingress.kubernetes.io/auth-realm" "Authentication Required") -}}
{{- end -}}

{{- $annotations = mustMergeOverwrite $annotations ($configuration.ingress.extraAnnotations | default dict) -}}
{{- $annotations = mustMergeOverwrite $annotations ($endpoint_config.extraAnnotations | default dict) -}}

---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  namespace: {{ $.Values.namespace }}
  name: {{ $serviceType }}-{{ $nameLabel }}-{{ $endpoint_definition }}
  labels:
    app: {{ $serviceType }}
    endpoint-definition: {{ $endpoint_definition }}
  annotations: {{ $annotations | toYaml | nindent 4 }}
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
        pathType: {{ get $path_config "pathType" | default "Prefix" }}
        backend:
          service:
            name: {{ $serviceType }}
            port:
              number: {{ $port }}
      {{ end }}
  {{- end }}
  {{- if and (or $configuration.ingress.tlsEnabled $endpoint_config.tlsEnabled) $configuration.ingress.secretName }}
  tls:
  - hosts:
    {{- range $host := $hosts }}
    {{/* basic filtering so crt contains dns compliant host entries */}}
    {{- if contains "." $host -}}
    - {{ $host }}
    {{- end }}
    {{- end }}
    secretName: {{ $configuration.ingress.secretName }}
  {{- end }}
{{ end }}
{{ end }}
