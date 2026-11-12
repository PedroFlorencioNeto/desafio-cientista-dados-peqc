{% test valor_entre(model, column_name, minimo, maximo) %}

-- Teste genérico: falha se algum valor da coluna estiver fora de [minimo, maximo].
-- Nulos são ignorados de propósito: verificar nulos é papel do not_null.

select
    {{ column_name }} as valor_fora_do_intervalo
from {{ model }}
where {{ column_name }} < {{ minimo }}
   or {{ column_name }} > {{ maximo }}

{% endtest %}
