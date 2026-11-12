-- Taxa de absenteísmo crônico por região (bairro anonimizado da escola).
-- A taxa da região é recalculada a partir das CONTAGENS, e não pela média das taxas.
select
    hash_bairro_escola,
    count(*)                    as qtd_escolas,
    sum(qtd_alunos_elegiveis)   as alunos_elegiveis,
    sum(qtd_alunos_cronicos)    as alunos_cronicos,
    round(100 * safe_divide(sum(qtd_alunos_cronicos), sum(qtd_alunos_elegiveis)), 2)
                                as taxa_correta,
    round(avg(taxa_absenteismo_cronico), 2)
                                as media_das_taxas_errada
from {{ ref('mart_educacao__absenteismo_escola') }}
group by hash_bairro_escola
having sum(qtd_alunos_elegiveis) >= 100
order by taxa_correta desc
