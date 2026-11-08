{# Liefert die Data-Manager-Quelle – oder die Beispieldaten, wenn use_sample_data = true. #}
{% macro dm_source(name) -%}
  {%- if var('use_sample_data') | as_bool -%}
    {{ ref('sample__' ~ name) }}
  {%- else -%}
    {{ source('data_manager', name) }}
  {%- endif -%}
{%- endmacro %}
