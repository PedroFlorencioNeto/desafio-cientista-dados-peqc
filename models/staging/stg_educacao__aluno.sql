with

fonte as (
    select * from {{ source('educacao', 'aluno') }}
),

tratado as (
    select
        -- identificadores
        -- id_aluno vem como BYTES do Parquet; base64 gera um texto estável e
        -- idêntico em todas as tabelas, garantindo joins consistentes
        to_base64(id_aluno)  as id_aluno,
        id_turma,

        -- atributos
        faixa_etaria,
        bairro               as hash_bairro_residencia  -- hash: não tem significado legível

    from fonte
)

select * from tratado
