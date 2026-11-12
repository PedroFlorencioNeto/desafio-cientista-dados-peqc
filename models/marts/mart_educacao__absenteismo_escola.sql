with

aluno_bimestre as (
    select * from {{ ref('int_educacao__aluno_bimestre') }}
),

-- 1 linha por aluno: quantos bimestres têm frequência informada e quantos
-- ficaram abaixo do limite. A frequência vem de stg_educacao__avaliacao.
por_aluno as (
    select
        id_aluno,
        id_escola_atual,
        hash_bairro_escola,
        countif(pct_frequencia is not null)                              as qtd_bimestres_com_frequencia,
        countif(pct_frequencia < {{ var('limite_frequencia_minima') }})  as qtd_bimestres_abaixo_limite,
        avg(pct_frequencia)                                              as pct_frequencia_media
    from aluno_bimestre
    group by id_aluno, id_escola_atual, hash_bairro_escola
),

-- Classificação em três estados: crônico (true), não crônico (false) e
-- não avaliável (null), para alunos com menos bimestres informados do que
-- a definição exige. Sem o "case", esses alunos seriam sempre "false" por
-- falta de dados, e não por evidência.
classificado as (
    select
        *,
        qtd_bimestres_com_frequencia >= {{ var('qtd_bimestres_cronico') }}
            as is_elegivel,
        case
            when qtd_bimestres_com_frequencia >= {{ var('qtd_bimestres_cronico') }}
            then qtd_bimestres_abaixo_limite  >= {{ var('qtd_bimestres_cronico') }}
        end as is_absenteista_cronico
    from por_aluno
),

por_escola as (
    select
        id_escola_atual                as id_escola,
        hash_bairro_escola,
        count(*)                       as qtd_alunos,
        countif(is_elegivel)           as qtd_alunos_elegiveis,
        countif(is_absenteista_cronico) as qtd_alunos_cronicos,
        avg(pct_frequencia_media)      as pct_frequencia_media
    from classificado
    group by id_escola_atual, hash_bairro_escola
),

com_taxa as (
    select
        *,

        -- denominador = só alunos elegíveis (com dados suficientes)
        -- safe_divide devolve null em vez de erro se o denominador for 0
        100 * safe_divide(qtd_alunos_cronicos, qtd_alunos_elegiveis)
            as taxa_absenteismo_cronico,

        -- escolas pequenas têm taxas instáveis: 1 aluno a mais muda tudo
        qtd_alunos_elegiveis >= {{ var('min_alunos_amostra') }}
            as possui_amostra_suficiente

    from por_escola
),

final as (
    select
        *,

        -- ranking só entre escolas com amostra suficiente (1 = pior taxa)
        case
            when possui_amostra_suficiente then
                rank() over (
                    partition by possui_amostra_suficiente
                    order by taxa_absenteismo_cronico desc
                )
        end as ranking_absenteismo

    from com_taxa
)

select * from final
