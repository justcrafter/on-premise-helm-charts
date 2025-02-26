{{/*
Create upstream nginx entry for found navi-back service
*/}}
{{- define "front.renderUpstream" -}}
    {{- $service := .service -}}
    {{- $upstream := $service.metadata.name -}}
    {{- $ctx := .context -}}
    {{- printf "upstream %s {\n" $upstream }}
    {{- printf "    server %s;\n" $upstream }}
    {{- if $ctx.Values.front.keepalive.enabled -}}
    {{- printf "    keepalive %d;\n" (int $ctx.Values.front.keepalive.connections) }}
    {{- printf "    keepalive_requests %d;\n" (int $ctx.Values.front.keepalive.requests) }}
    {{- printf "    keepalive_time %s;\n" $ctx.Values.front.keepalive.time }}
    {{- printf "    keepalive_timeout %s;\n" $ctx.Values.front.keepalive.timeout }}
    {{- end -}}
    {{- printf "}\n" }}
{{- end -}}

{{/*
Create location nginx entry for found navi-back service
Render location only if rule is not empty string
Tsp-carrouting requires splitter
*/}}
{{- define "front.renderLocation" -}}
    {{- $service := .service -}}
    {{- $rule := get $service.metadata.labels "rule" }}
    {{- $ctx := .context -}}
    {{- if (ne $rule "") -}}
        {{- printf "location /%s {\n" $rule }}
        {{- printf "\n" }}
        {{- include "front.getInternalACL" $ctx | indent 4 }}
        {{- printf "\n" }}
        {{- printf "    rewrite ^/%s(.*)$ $1 break;\n" $rule }}
        {{- printf "    add_header X-Region %s always;\n" $service.metadata.name }}
        {{- if $ctx.Values.front.keepalive.enabled -}}
        {{- printf "    proxy_set_header Connection \"\";\n" }}
        {{- printf "    proxy_http_version 1.1;\n" }}
        {{- end -}}
        {{- printf "    proxy_pass http://%s$uri$is_args$args;\n" $service.metadata.name }}
        {{- printf "}\n" }}
        {{- if $ctx.Values.front.tsp_carrouting.enabled -}}
        {{- if hasSuffix "splitter" $service.metadata.name -}}
        {{- $back_host := $service.metadata.name | replace "-splitter" "-back" -}}
        {{- printf "location /tsp_%s {\n" $rule }}
        {{- printf "\n" }}
        {{- include "front.getInternalACL" $ctx | indent 4 }}
        {{- printf "\n" }}
        {{- printf "    rewrite ^/tsp_%s(.*)$ $1 break;\n" $rule }}
        {{- printf "    add_header X-Region %s always;\n" $service.metadata.name }}
        {{- printf "    proxy_set_header X-Splitter-Host http://%s;\n" $service.metadata.name }}
        {{- printf "    proxy_set_header X-Moses-Host http://%s;\n" $back_host }}
        {{- if $ctx.Values.front.keepalive.enabled -}}
        {{- printf "    proxy_set_header Connection \"\";\n" }}
        {{- printf "    proxy_http_version 1.1;\n" }}
        {{- end -}}
        {{- printf "    proxy_pass http://%s$uri$is_args$args;\n" $ctx.Values.front.tsp_carrouting.host }}
        {{- printf "}\n" }}
        {{- end -}}
        {{- end -}}
    {{- end -}}
{{- end -}}

{{/*
Checking that the back service is valid
*/}}
{{- define "front.isValidBackService" -}}
    {{- $service := .service -}}
    {{- $is_valid := false -}}
    {{- $navigroup := default "" .context.Values.navigroup -}}
    {{/* Supported back implementations: navi-back, mock, splitter */}}
    {{- if
    and
    (has (get $service.metadata.labels "app.kubernetes.io/name") (list "navi-back" "mock" "splitter" "navi-splitter"))
    (eq (get $service.metadata.labels "navigroup") $navigroup)
    (not (get $service.metadata.labels "behindSplitter"))
    -}}
        {{- $is_valid = true -}}
    {{- end -}}
    {{- ternary "true" "" $is_valid -}}
{{- end -}}

{{/*
Checking that the router service is valid
*/}}
{{- define "front.isValidRouterService" -}}
    {{- $service := .service -}}
    {{- $is_valid := false -}}
    {{- $navigroup := default "" .context.Values.navigroup -}}
    {{- if
    and
    (has (get $service.metadata.labels "app.kubernetes.io/name") (list "mrouter" "navi-router"))
    (eq (get $service.metadata.labels "navigroup") $navigroup) -}}
        {{- $is_valid = true -}}
    {{- end -}}
    {{- ternary "true" "" $is_valid -}}
{{- end -}}


{{/*
Create locations for rules upstreams
*/}}
{{- define "front.createLocations" -}}
{{- $ns := print .Release.Namespace -}}
{{- range $index, $service := (lookup "v1" "Service" $ns "").items -}}
    {{- if kindIs "map" $service.metadata.labels }}
        {{- if (include "front.isValidBackService" (dict "service" $service "context" $)) }}
            {{- include "front.renderLocation" (dict "service" $service "context" $) -}}
        {{- end }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Create upstreams for running navi-back in the namespace
*/}}
{{- define "front.createUpstreams" -}}
{{- $ns := print .Release.Namespace }}
{{- range $index, $service := (lookup "v1" "Service" $ns "").items -}}
    {{- if kindIs "map" $service.metadata.labels }}
        {{- if (include "front.isValidBackService" ( dict "service" $service "context" $)) }}
            {{- include "front.renderUpstream" ( dict "service" $service "context" $) }}
        {{- end }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Create upstreams for running navi-router in the namespace
*/}}
{{- define "front.createRouterUpstream" -}}
{{- $location := "router" -}}
{{- $ns := print .Release.Namespace -}}
{{- range $index, $service := (lookup "v1" "Service" $ns "").items -}}
    {{- if kindIs "map" $service.metadata.labels }}
        {{- if (include "front.isValidRouterService" ( dict "service" $service "context" $)) }}
            {{- $location = $service.metadata.name -}}
            {{- print $location -}}
        {{- end }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Render ACL for private locations
*/}}
{{- define "front.getInternalACL" }}
{{- if not (and (hasKey .Values.nginx.protectInternalLocations "disabled") .Values.nginx.protectInternalLocations.disabled) -}}
    {{- if .Values.nginx.protectInternalLocations.allowedNetworks -}}
        {{- range .Values.nginx.protectInternalLocations.allowedNetworks -}}
        {{- printf "allow %s;\n" . }}
        {{- end -}}{{/* range */}}
        {{- printf "deny all;\n" }}
    {{- else -}}
        {{- printf "internal;\n" }}
    {{- end -}}{{/* .Values.nginx.protectInternalLocations.allowedNetworks */}}
{{- end -}}{{/* .Values.nginx.protectInternalLocations.disabled */}}
{{- end -}}
