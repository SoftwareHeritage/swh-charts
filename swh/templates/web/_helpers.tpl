# -*- yaml -*-

{{/*
Generate the configuration for the webapp throttling configuration
*/}}
{{- define "swh.web.throttling" -}}
{{- $configuration := get .Values .configurationRef -}}
{{- $internalExemptedNetworks := get .Values (get $configuration "internalExemptedNetworkRangesRef") | default list -}}
{{- $externalExemptedNetworks := get .Values (get $configuration "externalExemptedNetworkRangesRef") | default list -}}
{{- $exemptedNetworks := concat $internalExemptedNetworks $externalExemptedNetworks -}}
throttling:
  cache_uri: {{ get $configuration "cache_uri" }}
  scopes:
    {{- range $role, $role_config := get $configuration "scopes_with_exempted_networks" -}}
    {{- $localExemptedNetworks := get $role_config "exempted_networks" | default list -}}
    {{- $allLocalExemptedNetworks := concat $exemptedNetworks $localExemptedNetworks | uniq | sortAlpha -}}
    {{- if $allLocalExemptedNetworks -}}
      {{- $role_config := set $role_config "exempted_networks" $allLocalExemptedNetworks -}}
    {{- end }}
    {{ $role }}:
    {{- toYaml $role_config | nindent 6 }}
    {{- end -}}
    {{- range $role, $role_config := get $configuration "scopes" }}
    {{ $role }}:
    {{- toYaml $role_config | nindent 6 }}
    {{- end -}}
{{- end -}}
