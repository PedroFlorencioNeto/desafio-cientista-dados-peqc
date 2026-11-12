# Desafio de Ciência de Dados - RMI 

Autor: Pedro Florencio de Almeida Neto

## Resumo

Este projeto transforma cinco tabelas educacionais anonimizadas do Registro Municipal Integrado em um indicador de absenteísmo crônico por escola e região. A exploração feita antes da modelagem mostrou que a frequência mínima registrada na tabela de frequência é de 97,33%. Com esse piso, nenhum aluno fica abaixo de 75%, o que pode indicar um erro da carga dos dados ou um equívoco no cálculo da métrica. A frequência usada é, então, a bimestral registrada na tabela de avaliação. Dos 57.561 alunos com dados suficientes para classificação, 4.072 (7,07%) tiveram frequência abaixo de 75% em dois ou mais bimestres. Nas 401 escolas com amostra estável, a taxa varia de 0% a 20%, com mediana de 6,9%. O projeto tem 8 models e 49 testes, e o `dbt build` termina sem erros.

## 1. Pergunta

Das duas perguntas sugeridas no desafio, escolhi a do absenteísmo crônico, porque ela leva a uma ação direta: uma ordenação de escolas e regiões para priorizar acompanhamento e busca ativa. Considero absenteísta crônico o aluno com frequência abaixo de 75% em pelo menos dois bimestres. O limite de 75% é a frequência mínima exigida pela LDB (Lei 9.394/96, art. 24, VI). A exigência de dois bimestres separa um padrão persistente de um episódio isolado, como uma doença.

## 2. Diagnóstico dos dados

Os Parquets do bucket foram carregados com `bq load` em um dataset `raw` na região US, a mesma de `datario.dados_mestres`, já que o BigQuery não executa joins entre regiões. Toda a exploração foi feita em SQL antes de qualquer model ser escrito, e os achados abaixo determinaram o desenho do projeto. Parte das consultas usadas, com os comentários que registram as decisões tomadas a partir delas, está em `eda/exploracao.sql`.

| Achado | Evidência | Consequência |
|---|---|---|
| Frequência da tabela de frequência não representa o absenteísmo | A frequência mínima de `stg_educacao__frequencia` é 97,33%, então nenhum aluno fica abaixo de 75%. | O indicador usa a frequência bimestral de `stg_educacao__avaliacao` (0 a 100, média de 89%); a coluna da tabela de frequência é mantida sem correção como `indice_frequencia_reportado` |
| `id_turma` inconsistente entre tabelas | Em 99,99% das linhas de frequência, a turma difere da registrada no cadastro do aluno | Joins feitos por `id_aluno`, que não tem órfãos em nenhuma tabela |
| Frequência cobre só o primeiro semestre | Mais de 96% dos alunos têm registro até 17/jul; depois, menos de 1% | Mais um motivo para usar a avaliação, que cobre os quatro bimestres |
| Duplicatas no grão | 2.576 linhas na frequência (1.093 grupos com valores conflitantes) e 34 na avaliação | Deduplicação no staging com critério explícito |
| Tipos diferentes do dicionário | `id_aluno` chega como BYTES e `bimestre` como STRING | `to_base64()` e `cast` no staging |
| Descrição do desafio diferente dos dados | A frequência não é diária; `turma` é uma relação aluno–turma sem série nem turno; `escola` não tem tipo nem região | Descrições corrigidas nos YAML |

## 3. Modelagem

O fluxo segue as camadas staging, intermediate e marts. No diagrama, os nomes estão abreviados; os arquivos levam o prefixo da fonte (`stg_frequencia` é `stg_educacao__frequencia`, e assim por diante).

```
raw           staging           intermediate
─────────────────────────────────────────────────────────────────────────
frequencia ─► stg_frequencia ─► int_aluno_escola_atual ─┐
avaliacao  ─► stg_avaliacao  ───────────────────────────┤
aluno      ─► stg_aluno      ───────────────────────────┼─► int_aluno_bimestre
escola     ─► stg_escola     ───────────────────────────┘          │
turma      ─► stg_turma        (sem dependentes)                   ▼
                                               marts    mart_absenteismo_escola
```

**Staging.** Há um model por tabela de origem, limitado a renomear, tipar e deduplicar. Nas duplicatas conflitantes da frequência, mantenho o menor valor, uma postura conservadora que não esconde faltas. Na avaliação, as duplicatas costumam ser um par em que uma das linhas está vazia, então fica a linha mais completa, com desempate pela menor frequência. Todo `row_number()` termina em um critério de desempate determinístico, para que duas execuções sobre os mesmos dados produzam o mesmo resultado. A avaliação ganha a flag `possui_nota`, porque 15% das linhas não têm nenhuma nota mas ainda carregam frequência. O `stg_educacao__turma` não alimenta nenhum model, já que repete o `id_turma` do cadastro de alunos. Ele existe para completar a camada e é usado em um teste singular.

**Intermediate.** O `int_educacao__aluno_escola_atual` resolve a única ligação entre aluno e escola, que só existe na tabela de frequência. Como 3.483 alunos aparecem em mais de uma escola, cada um é atribuído à escola do registro mais recente, porque é a gestão atual que responde pela frequência do aluno. Os empates são resolvidos pelo maior número de registros (293 casos) e, por fim, pelo menor `id_escola` (7 casos). O `int_educacao__aluno_bimestre` tem grão aluno × bimestre e parte da avaliação com `left join` para aluno, escola atual e escola. Todas as tabelas à direita têm no máximo uma linha por chave, o que impede a multiplicação de linhas. Um eventual órfão vira nulo e é capturado pelos testes `not_null` da camada; hoje não há nenhum. Os 538 alunos que trocaram de turma dentro de um bimestre têm os dois registros combinados por média. Nesse caso os dois registros são legítimos, diferentemente das duplicatas conflitantes do staging, em que só um pode ser verdadeiro.

**Mart.** Há um único mart, o `mart_educacao__absenteismo_escola`. Ele primeiro classifica cada aluno, numa CTE interna, e depois agrega por escola. Alunos com menos de dois bimestres de frequência informada (11.941) não conseguem satisfazer a definição por construção. Por isso são tratados como "não avaliáveis", e não como não crônicos, e ficam fora do denominador da taxa. O mart guarda o numerador e o denominador, além da taxa, para que agregações por região somem contagens em vez de tirar média de taxas. Escolas com menos de 30 alunos elegíveis recebem uma flag de amostra insuficiente e ficam fora do ranking. Os três limites (75%, dois bimestres e 30 alunos) são `vars` do `dbt_project.yml`.

**Convenções.** Os models seguem o padrão `<camada>_<fonte>__<entidade>`, e as colunas usam prefixos que indicam o conteúdo: `id_`, `hash_`, `pct_`, `nota_`, `qtd_`, `is_` e `possui_`. Staging e intermediate são views, porque a lógica é leve e assim sempre refletem o dado bruto. O mart é uma table, porque é consultado diretamente. A materialização incremental foi descartada porque o BigQuery Sandbox não permite DML, e o incremental depende de `MERGE`. A agregação por região fica versionada em `analyses/`. Usei o dbt Core 1.12, e não o dbt v2, porque o enunciado pede `dbt-core` e os pacotes da comunidade ainda têm como alvo a v1.

## 4. Testes

Um teste entra no projeto quando o código depende da premissa que ele verifica, quando a violação produziria um resultado errado sem nenhum erro aparente, e sempre na camada mais próxima da origem em que o problema pode ser detectado. Seguindo esse critério, as chaves de `aluno` e `escola` são testadas como `unique` e `not_null` já nas sources e de novo no staging. Domínios usados em agrupamentos ou em expressões `CASE` recebem `accepted_values`: faixa etária, bimestre, ano letivo e código de disciplina. Este último vem acompanhado de um `not_null` no nome da disciplina, que captura um código novo que o `CASE` não reconheça. Os `relationships` verificam órfãos em frequência, avaliação e turma, e as colunas vindas de `left join` no intermediate têm `not_null`. No mart, o grão é testado com `unique`, e o ranking com um `not_null` restrito, por `where`, às escolas com amostra suficiente. Os nulos já conhecidos (68 bairros de residência e 1.713 frequências bimestrais) não são ignorados: são monitorados com `warn_if: ">0"` e com um `error_if` acima do volume atual, de modo que aparecem como aviso em toda execução e passam a falhar se o problema crescer. Ficaram de fora, de propósito, os `not_null` em colunas cujos nulos foram aceitos e a repetição de `relationships` nas camadas seguintes. A justificativa de cada teste está em comentário no próprio YAML.

As regras de negócio estão em três testes singulares em `tests/`, cada um com um cabeçalho que descreve a regra, por que ela importa e como é verificada. O primeiro garante que nenhum período de apuração termina antes de começar. O segundo garante que toda frequência cai no ano letivo da turma do aluno, com a ligação feita por `id_aluno`. O terceiro recalcula, a partir do intermediate e por um caminho independente do mart, os totais de alunos, elegíveis e crônicos de cada escola, e compara os dois com `full outer join` e `is distinct from`, o que captura também escolas ausentes de um dos lados. Há ainda um teste genérico próprio, `valor_entre`, aplicado às quatro notas (de 0 a 10), à frequência bimestral e à taxa da escola (de 0 a 100).

Os testes foram validados também por falha induzida. Rodando o teste de contagens com o limite de 80% contra um mart construído com 75%, ele acusa divergência em 481 das 521 escolas. No estado atual, os 49 testes resultam em 47 aprovações e 2 avisos intencionais.

## 5. Resultados

Dos 69.502 alunos com avaliação, 57.561 têm ao menos dois bimestres de frequência informada e entram no cálculo. Entre eles, 4.072 são absenteístas crônicos e 53.489 não são, o que dá uma taxa de 7,07% na rede. Os 11.941 restantes (17%) não são avaliáveis.

Das 521 escolas, 401 têm pelo menos 30 alunos elegíveis. Nelas, a taxa de absenteísmo crônico tem mediana de 6,9% e intervalo interquartil de 5,5% a 8,3%; a maior taxa é de 20% (6 de 30 alunos). As taxas mais altas da base, de 30%, aparecem em escolas com apenas 10 alunos elegíveis, onde três alunos bastam para chegar a esse valor, e isso justifica a flag de amostra. Por região, 106 dos 135 bairros com escola têm pelo menos 100 alunos elegíveis, e a taxa entre eles vai de 2,6% a 11,8%. A agregação regional em `analyses/absenteismo_por_regiao.sql` mostra por que a taxa precisa ser recalculada a partir das contagens: em um dos bairros, a média simples das taxas das escolas dá 5,1%, enquanto a taxa real é de 9,9%.

A dispersão entre escolas é moderada: metade delas fica entre 5,5% e 8,3%, e as que se destacam acima disso são as candidatas naturais a acompanhamento prioritário. A flag de amostra é o que impede o ranking de ser dominado por escolas pequenas, cujas taxas extremas refletem poucos alunos e não um padrão. Os 17% de alunos não avaliáveis merecem atenção à parte, porque alunos com poucos bimestres registrados podem ser justamente os que entraram tarde ou deixaram a rede, e o indicador, por construção, não os enxerga. Por fim, os dados foram aleatorizados na anonimização. Os números demonstram o funcionamento do modelo, não um diagnóstico da rede.

## 6. Limitações

O indicador cobre os 69.502 alunos com avaliação, e não os 97.044 do cadastro, e a cobertura da avaliação cai de 69% dos alunos no primeiro bimestre para 46% no quarto. A regra da escola atual atribui à escola nova faltas ocorridas antes da transferência. A região é um bairro anonimizado, sem nome nem vínculo com as regiões administrativas. A exigência de dois bimestres equivale a 50% dos bimestres para quem tem quatro registros e a 100% para quem tem dois, o que torna a régua mais rígida para alunos com menos dados. O grão composto do `stg_educacao__frequencia` é garantido pela deduplicação, mas não é testado diretamente, porque o projeto não usa pacotes. Por último, o BigQuery Sandbox apaga tabelas 60 dias após a criação: as tabelas de `raw` carregadas para este trabalho expiram em 9 de janeiro de 2027 e precisam ser recarregadas depois disso.

## 7. Como reproduzir

O projeto foi executado no Windows 11 com PowerShell, Python 3.12.10, dbt Core 1.12.6 e dbt-bigquery 1.12.2. É preciso ter o [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) instalado e uma conta Google com um projeto no Google Cloud. O BigQuery Sandbox é suficiente e não exige cartão de crédito.

**Ambiente Python.** Clone o repositório e crie um ambiente virtual com Python 3.12. Versões mais novas do Python podem ainda não ser suportadas por todas as dependências do dbt. No Linux ou macOS, a ativação é `source env-dbt/bin/activate`.

```powershell
git clone https://github.com/PedroFlorencioNeto/desafio-cientista-dados-peqc.git
cd desafio-cientista-dados-peqc
py -V:3.12 -m venv env-dbt
.\env-dbt\Scripts\Activate.ps1
pip install -r requirements.txt
dbt --version
```

**Autenticação no Google Cloud.** São dois logins. O primeiro autentica as ferramentas de linha de comando (`gcloud` e `bq`). O segundo gera as Application Default Credentials, que o dbt usa por meio de `method: oauth` no `profiles.yml`, sem nenhuma chave gravada no repositório. A variável `DBT_GCP_PROJECT` diz ao dbt em qual projeto trabalhar; se não for definida, o `profiles.yml` usa `rmi-desafio`. No Linux ou macOS, use `export DBT_GCP_PROJECT=seu-projeto`.

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project SEU_PROJETO
$env:DBT_GCP_PROJECT = "SEU_PROJETO"
```

**Carga dos dados brutos.** Os arquivos do bucket não têm extensão e são baixados para `data/` já como `.parquet`. A pasta está no `.gitignore`. O dataset `raw` precisa ficar na região US. O schema de cada tabela vem do próprio Parquet.

```powershell
foreach ($t in "aluno","escola","turma","frequencia","avaliacao") {
    gcloud storage cp "gs://case_vagas/rmi/$t" "data/$t.parquet"
}
bq --location=US mk --dataset "${env:DBT_GCP_PROJECT}:raw"
foreach ($t in "aluno","escola","turma","frequencia","avaliacao") {
    bq load --source_format=PARQUET "raw.$t" "data/$t.parquet"
}
```

Ao final, `raw` deve ter 97.044 linhas em `aluno`, 1.558 em `escola`, 97.044 em `turma`, 2.727.684 em `frequencia` e 221.687 em `avaliacao`.

**Execução do dbt.** O `dbt debug` confirma que o `dbt_project.yml` e o `profiles.yml` foram encontrados e que a conexão funciona. O `dbt build` cria cada model e roda os testes dele antes de seguir para os dependentes, na ordem do grafo. Se um teste falhar, o que vem depois é pulado.

```powershell
dbt debug
dbt build
```

A execução cria os datasets `dbt_dev_staging`, `dbt_dev_intermediate` e `dbt_dev_marts` e termina com `PASS=55 WARN=2 ERROR=0`: 8 models e 49 testes, dos quais 2 são os avisos de nulos monitorados descritos na seção 4. Para reconstruir só uma parte do grafo, use `dbt build --select +mart_educacao__absenteismo_escola`, que inclui tudo de que o mart depende. Para testar outro limite de frequência sem editar arquivos, use `dbt build --select marts --vars '{limite_frequencia_minima: 80}'`.

**Documentação e análises.** O primeiro comando abaixo gera a documentação com o grafo de lineage, e o segundo a serve em `http://localhost:8080`. A consulta de `analyses/` não é executada pelo dbt, só compilada. O SQL pronto fica em `target/compiled/rmi_educacao/analyses/` e pode ser rodado no console do BigQuery.

```powershell
dbt docs generate
dbt docs serve
dbt compile --select absenteismo_por_regiao
```

## Declaração de uso de IA

Devido ao prazo e pouca experiência com dbt, este trabalho contou com o Claude (Anthropic) na revisão do código SQL e YAML e na redação desta documentação. A escolha da pergunta, o planejamento do projeto e as decisões de modelagem e de teste são meus, entre elas o critério de deduplicação, a regra de atribuição da escola atual e a definição de absenteísmo crônico. O aprendizado da ferramenta contou com leitura de documentações e cursos rápidos no YouTube. Agradeço a oportunidade de chegar até aqui ❤️
