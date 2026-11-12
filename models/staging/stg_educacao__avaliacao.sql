with

fonte as (
    select * from {{ source('educacao', 'avaliacao') }}
),

tratado as (
    select
        -- identificadores
        to_base64(id_aluno)      as id_aluno,
        id_turma,
        cast(bimestre as int64)  as bimestre,  -- veio como STRING

        -- métricas
        frequencia               as pct_frequencia,   -- percentual real, 0 a 100
        disciplina_1             as nota_portugues,
        disciplina_2             as nota_ciencias,
        disciplina_3             as nota_ingles,
        disciplina_4             as nota_matematica

    from fonte
),

com_flags as (
    select
        *,

        -- 15% das linhas não têm nenhuma nota, mas têm frequência: são mantidas
        -- e sinalizadas, para não distorcer as métricas de absenteísmo
        coalesce(nota_portugues, nota_ciencias, nota_ingles, nota_matematica) is not null
            as possui_nota,

        -- usado só para escolher a linha mais completa na deduplicação
          if(pct_frequencia  is not null, 1, 0)
        + if(nota_portugues  is not null, 1, 0)
        + if(nota_ciencias   is not null, 1, 0)
        + if(nota_ingles     is not null, 1, 0)
        + if(nota_matematica is not null, 1, 0)
            as qtd_campos_preenchidos

    from tratado
),

deduplicado as (
    -- 34 linhas repetidas por aluno/turma/bimestre; em geral uma delas está vazia.
    -- Regra: manter a mais completa; empate -> a de menor frequência.
    select * except (qtd_campos_preenchidos)
    from com_flags
    qualify row_number() over (
        partition by id_aluno, id_turma, bimestre
        order by qtd_campos_preenchidos desc, pct_frequencia asc nulls last
    ) = 1
)

select * from deduplicado
