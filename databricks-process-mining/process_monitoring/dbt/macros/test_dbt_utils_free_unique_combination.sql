{# Eindeutigkeit einer Spaltenkombination (ohne Paket-Abhängigkeit). #}
{% test dbt_utils_free_unique_combination(model, columns) %}
SELECT {{ columns | join(', ') }}, COUNT(*) AS n
FROM {{ model }}
GROUP BY {{ columns | join(', ') }}
HAVING COUNT(*) > 1
{% endtest %}
