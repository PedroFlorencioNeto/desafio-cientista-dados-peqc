with

avaliacao as (
    select * from {{ ref('stg_educacao__avaliacao') }}
),

aluno as (
    select * from {{ ref('stg_educacao__aluno') }}
),

escola_atual as (
    select * from {{ ref('int_educacao__aluno_escola_atual') }}
),

escola as (
    select * from {{ ref('stg_educacao__escola') }}
),

-- 538 alunos trocaram de turma dentro de um mesmo bimestre e aparecem em 2 linhas.
-- Os dois registros são legítimos (não são duplicatas), então são combinados por média.
avaliacao_por_bimestre as (
    select
        id_aluno,
        bimestre,
        count(*)              as qtd_turmas_no_bimestre,
        avg(pct_frequencia)   as pct_frequencia,
        avg(nota_portugues)   as nota_portugues,
        avg(nota_ciencias)    as nota_ciencias,
        avg(nota_ingles)      as nota_ingles,
        avg(nota_matematica)  as nota_matematica,
        logical_or(possui_nota) as possui_nota
    from avaliacao
    group by id_aluno, bimestre
),

final as (
    select
        -- chaves
        av.id_aluno,
        av.bimestre,
        ea.id_escola_atual,

        -- atributos do aluno e da escola
        al.faixa_etaria,
        es.hash_bairro_escola,
        ea.foi_transferido,

        -- métricas do bimestre
        av.pct_frequencia,
        av.nota_portugues,
        av.nota_ciencias,
        av.nota_ingles,
        av.nota_matematica,

        -- média das notas disponíveis (ignora disciplinas sem nota)
        (
            select avg(nota)
            from unnest([av.nota_portugues, av.nota_ciencias,
                         av.nota_ingles,    av.nota_matematica]) as nota
        ) as media_notas,

        av.possui_nota,
        av.qtd_turmas_no_bimestre

    from avaliacao_por_bimestre as av

    -- LEFT JOINs: o grão é definido pela avaliação (aluno x bimestre).
    -- Nenhuma linha é descartada se faltar correspondência; os nulos
    -- resultantes são capturados por testes not_null (Aula 9).
    -- Exploração: 0 órfãos em todos os joins.
    left join aluno        as al on av.id_aluno = al.id_aluno
    left join escola_atual as ea on av.id_aluno = ea.id_aluno
    left join escola       as es on ea.id_escola_atual = es.id_escola
)

select * from final
