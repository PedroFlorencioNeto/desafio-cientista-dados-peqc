-- REGRA: todo registro de frequência de um aluno deve estar dentro do ano
--        letivo da turma desse aluno.
-- POR QUE IMPORTA: frequência de outro ano misturaria anos letivos nas métricas
--        de absenteísmo, inflando ou reduzindo as taxas sem nenhum erro aparente.
--        Hoje o ano está anonimizado (sempre 2000), mas, quando houver mais de um
--        ano na base, esta regra é a que impede a mistura.
-- COMO: liga frequência e turma pelo aluno (id_turma não é confiável entre
--        tabelas, ver README) e devolve registros com ano diferente.

with

frequencia as (
    select * from {{ ref('stg_educacao__frequencia') }}
),

turma as (
    select * from {{ ref('stg_educacao__turma') }}
)

select
    f.id_aluno,
    f.data_inicio,
    f.data_fim,
    t.ano_letivo
from frequencia as f
inner join turma as t
    on f.id_aluno = t.id_aluno
where extract(year from f.data_inicio) != t.ano_letivo
   or extract(year from f.data_fim)    != t.ano_letivo
