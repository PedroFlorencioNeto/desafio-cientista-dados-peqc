with

frequencia as (
    select * from {{ ref('stg_educacao__frequencia') }}
),

-- passo 1: resume a frequência para 1 linha por aluno x escola
por_aluno_escola as (
    select
        id_aluno,
        id_escola,
        max(data_fim)  as data_ultimo_registro,
        count(*)       as qtd_registros
    from frequencia
    group by id_aluno, id_escola
),

-- passo 2: ordena as escolas de cada aluno, da "mais atual" para a menos
ranqueado as (
    select
        *,
        count(*) over (partition by id_aluno) as qtd_escolas_frequentadas,
        row_number() over (
            partition by id_aluno
            order by
                data_ultimo_registro desc,  -- regra: escola do registro mais recente
                qtd_registros        desc,  -- desempate 1: onde passou mais tempo (293 casos)
                id_escola            asc    -- desempate 2: determinismo (7 casos)
        ) as ordem
    from por_aluno_escola
),

-- passo 3: fica com a primeira de cada aluno
escola_atual as (
    select
        id_aluno,
        id_escola                     as id_escola_atual,
        data_ultimo_registro,
        qtd_escolas_frequentadas,
        qtd_escolas_frequentadas > 1  as foi_transferido
    from ranqueado
    where ordem = 1
)

select * from escola_atual
