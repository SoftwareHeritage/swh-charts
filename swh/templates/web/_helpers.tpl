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

{{/*
Generate the private api deposit configuration for the webapp (yaml is different than
the checkers & loaders's equivalent).
*/}}
{{- define "deposit.configuration.api.private" -}}
{{- $depositConfiguration := get .Values .configurationRef -}}
{{- $host := required (print "_helpers.tpl:deposit.configuration.api.private: The <host> property is mandatory in " $depositConfiguration)
                    (get $depositConfiguration "host") -}}
{{- $user := required (print "_helpers.tpl:deposit.configuration.api.private: The <user> property is mandatory in " $depositConfiguration)
                    (get $depositConfiguration "user") -}}
{{- $pass := required (print "_helpers.tpl:deposit.configuration.api.private: The <pass> property is mandatory in " $depositConfiguration)
                    (get $depositConfiguration "pass") -}}
deposit:
  private_api_url: https://{{ $host }}/1/private/
  private_api_user: {{ $user }}
  private_api_password: {{ $pass }}
{{- end -}}
