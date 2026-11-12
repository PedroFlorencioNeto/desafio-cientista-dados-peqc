# analisa os metadados das tabelas disponibilizadas
SELECT table_name, column_name, data_type
FROM raw.INFORMATION_SCHEMA.COLUMNS
ORDER BY table_name, ordinal_position
# comentarios:
# id_aluno no schema_original está como string e não "bytes"
# avaliacao.bimestre esta como INT64 no schema original

# verifica se existe 1 frequencia por aluno por dia, turma, disciplina e periodo
SELECT f.id_aluno, f.id_turma, f.disciplina, f.data_inicio, f.data_fim, COUNT(*) AS qtd_linhas, COUNT(DISTINCT f.frequencia) as qtd_valores_diferentes
FROM raw.frequencia as f
GROUP BY 1, 2, 3, 4, 5
HAVING COUNT(*) > 1
ORDER BY qtd_linhas DESC

# verifica quais valores sao inconsistentes
WITH grupos_conflitantes as (
  SELECT
    f.id_aluno, f.id_turma, f.disciplina, f.data_inicio, f.data_fim
  FROM raw.frequencia as f
  GROUP BY 1, 2, 3, 4, 5
  HAVING COUNT(DISTINCT f.frequencia) > 1     -- mais de um valor diferente = conflito
)

SELECT f.*
FROM raw.frequencia AS f
JOIN grupos_conflitantes AS g
  ON  f.id_aluno    = g.id_aluno
  AND f.id_turma    = g.id_turma
  AND f.disciplina  = g.disciplina
  AND f.data_inicio = g.data_inicio
  AND f.data_fim    = g.data_fim
ORDER BY f.id_aluno, f.disciplina, f.data_inicio
# comentarios:
# existem alunos com frequencias duplicadas para um mesmo dia, turma, disciplina e periodo. algumas frequencias sao identicas, outras possuem valores distintos.
# ao avaliar os valores conflitantes, tomou-se a decisão de manter a de menor frequência como uma postura mais conservadora de metodologia.

# avaliacao das duplicatas
SELECT a.*
FROM raw.avaliacao AS a
QUALIFY COUNT(*) OVER (PARTITION BY  a.id_aluno, a.id_turma, a.bimestre) > 1
ORDER BY a.id_aluno, a.bimestre
# comentarios:
# a decisao sobre a duplicata de avaliacao e manter os dados de avaliacao com maior completude de informacoes e realizar um desempate pela menor frequencia.

SELECT *
FROM raw.frequencia
LIMIT(5)

# Em 99,99% das linhas a turma da frequência não é a turma do cadastro
select
  count(*)                          as total,
  countif(f.id_turma =  t.id_turma) as turma_igual,
  countif(f.id_turma != t.id_turma) as turma_diferente
from raw.frequencia as f
join raw.turma as t
  on f.id_aluno = t.id_aluno      -- liga a frequência ao MESMO aluno no cadastro
