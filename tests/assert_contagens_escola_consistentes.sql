-- REGRA: para cada escola, os totais de alunos, elegíveis e crônicos do mart
--        devem seguir exatamente a definição de negócio: elegível = pelo menos N
--        bimestres com frequência informada; crônico = elegível com pelo menos N
--        bimestres abaixo do limite.
--        (N = var qtd_bimestres_cronico; limite = var limite_frequencia_minima)
-- POR QUE IMPORTA: é o indicador entregue aos gestores. Um erro na classificação
--        ou na agregação muda o ranking das escolas sem nenhum erro aparente.
-- COMO: recalcula as contagens por escola a partir do intermediate, por um
--        caminho independente do mart, e devolve as escolas em que os números
--        divergem (inclusive escolas presentes em só um dos lados).

with

recalculado_por_aluno as (
    select
        id_aluno,
        id_escola_atual,
        countif(pct_frequencia is not null)                              as bimestres_informados,
        countif(pct_frequencia < {{ var('limite_frequencia_minima') }})  as bimestres_abaixo
    from {{ ref('int_educacao__aluno_bimestre') }}
    group by id_aluno, id_escola_atual
),

esperado as (
    select
        id_escola_atual as id_escola,
        count(*) as qtd_alunos,
        countif(bimestres_informados >= {{ var('qtd_bimestres_cronico') }}) as qtd_elegiveis,
        countif(bimestres_informados >= {{ var('qtd_bimestres_cronico') }}
            and bimestres_abaixo     >= {{ var('qtd_bimestres_cronico') }}) as qtd_cronicos
    from recalculado_por_aluno
    group by id_escola_atual
),

mart as (
    select
        id_escola,
        qtd_alunos,
        qtd_alunos_elegiveis as qtd_elegiveis,
        qtd_alunos_cronicos  as qtd_cronicos
    from {{ ref('mart_educacao__absenteismo_escola') }}
)

select
    coalesce(e.id_escola, m.id_escola) as id_escola,
    e.qtd_alunos    as alunos_esperado,    m.qtd_alunos    as alunos_mart,
    e.qtd_elegiveis as elegiveis_esperado, m.qtd_elegiveis as elegiveis_mart,
    e.qtd_cronicos  as cronicos_esperado,  m.qtd_cronicos  as cronicos_mart
from esperado as e
full outer join mart as m
    on e.id_escola = m.id_escola
where e.qtd_alunos    is distinct from m.qtd_alunos
   or e.qtd_elegiveis is distinct from m.qtd_elegiveis
   or e.qtd_cronicos  is distinct from m.qtd_cronicos
