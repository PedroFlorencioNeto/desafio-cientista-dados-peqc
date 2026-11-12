with

fonte as (
    select * from {{ source('educacao', 'turma') }}
),

tratado as (
    select
        to_base64(id_aluno)  as id_aluno,
        id_turma,
        ano                  as ano_letivo  -- anonimizado: sempre 2000

    from fonte
)

select * from tratado
