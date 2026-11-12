-- REGRA: todo período de apuração de frequência termina na mesma data ou
--        depois de começar (data_fim >= data_inicio).
-- POR QUE IMPORTA: um período invertido indica erro de carga ou de conversão
--        de datas e tornaria qualquer cálculo de duração negativo.
-- COMO: devolve os registros com data_fim anterior a data_inicio.

select
    id_aluno,
    id_disciplina,
    data_inicio,
    data_fim
from {{ ref('stg_educacao__frequencia') }}
where data_fim < data_inicio
