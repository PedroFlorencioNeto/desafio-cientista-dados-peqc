with

fonte as (
    select * from {{ source('educacao', 'frequencia') }}
),

tratado as (
    select
        -- identificadores
        id_escola,
        to_base64(id_aluno)  as id_aluno,
        id_turma,
        disciplina           as id_disciplina,

        -- nome legível da disciplina, conforme o dicionário de dados original
        case disciplina
            when 'disciplina_1' then 'Língua Portuguesa'
            when 'disciplina_2' then 'Ciências'
            when 'disciplina_3' then 'Língua Estrangeira (Inglês)'
            when 'disciplina_4' then 'Matemática'
        end                  as nome_disciplina,

        -- datas chegam como texto 'AAAA-MM-DD'
        parse_date('%Y-%m-%d', data_inicio)  as data_inicio,
        parse_date('%Y-%m-%d', data_fim)     as data_fim,

        -- NÃO é um percentual real: a fórmula de origem omitiu o "x 100"
        -- (ver README, seção de qualidade de dados). Mantido sem correção.
        frequencia           as indice_frequencia_reportado

    from fonte
),

deduplicado as (
    -- 2.576 linhas repetidas no grão aluno/turma/disciplina/período, sendo
    -- 1.093 grupos com valores conflitantes. Regra: manter a MENOR frequência
    -- (postura conservadora: não esconder faltas).
    select *
    from tratado
    qualify row_number() over (
        partition by id_aluno, id_turma, id_disciplina, data_inicio, data_fim
        order by indice_frequencia_reportado asc, id_escola asc
    ) = 1
)

select * from deduplicado
