with

fonte as (
    select * from {{ source('educacao', 'escola') }}
),

tratado as (
    select
        id_escola,
        bairro  as hash_bairro_escola  -- hash diferente do de aluno: não são comparáveis

    from fonte
)

select * from tratado
