# Alojamento Local em Lisboa — indicadores para verificação

Análise investigativa de snapshots de anúncios Airbnb em Lisboa comparados com o registo oficial português de alojamento local. Os resultados são indicadores para verificação oficial, não conclusões jurídicas.

## Execução

```bash
bundle install
bundle exec rake sources:update
bundle exec rake analysis:local
```

A atualização das fontes, a análise e a construção do site são etapas independentes:

```bash
bundle exec rake sources:update   # verifica fontes remotas e descarrega se necessário
bundle exec rake analysis:local   # análise detalhada das fontes locais, sem rede
bundle exec rake analysis:public  # análise agregada publicável, sem rede
bundle exec rake site:build       # site a partir dos snapshots públicos existentes
```

Para executar as etapas seguintes em conjunto:

```bash
bundle exec rake refresh          # atualizar fontes → análise pública → site
bundle exec rake rebuild          # análise pública das fontes locais → site
```

`sources:update` consulta sempre o índice Inside Airbnb para Lisboa, mas só descarrega um CSV em falta. Reutiliza o RNAL datado mais recente se a sua data de download for igual ou posterior à data do snapshot Airbnb; caso contrário, descarrega uma cópia com a data real de hoje. Não procura uma versão histórica do RNAL nem altera a data de um ficheiro existente.

As tarefas de análise selecionam os ficheiros datados mais recentes em `data_sources/`. Se faltarem fontes, falham com indicação para executar `sources:update`. Para reproduzir um par histórico específico, use o script de reanálise descrito abaixo.

Por defeito, a análise é local e cria um run imutável detalhado em:

```text
data/private/<airbnb-snapshot-date>__<official-download-date>/
```

Runs locais são imutáveis. Cada nova análise do mesmo par de fontes cria automaticamente um diretório irmão com sufixo `__rerun-<timestamp>`, preservando os resultados anteriores.

Os resultados locais incluem diagnósticos como `host_id`, coordenadas e valores de licença originais e permanecem fora do Git. Para gerar os outputs agregados publicáveis, selecione explicitamente o modo público:

```bash
bundle exec rake analysis:public
```

Cada invocação recalcula a análise a partir das fontes locais. Não existe reutilização de resultados nem uma opção de force na análise; `REUSE_EXISTING` deixa de ser necessário. Uma reanálise pública valida os outputs antes de substituir o run do mesmo par de datas. Hashes diferentes para um par já publicado continuam a ser rejeitados.

`FORCE=1` pertence apenas à atualização das fontes: volta a descarregar o snapshot Airbnb mais recente e uma cópia RNAL com a data real de hoje, mesmo quando existem ficheiros locais adequados. Os downloads substituem o ficheiro datado apenas depois de concluídos; uma falha preserva a cópia anterior. Se os bytes de uma fonte com a mesma data mudarem, a proteção de proveniência da análise pública continua a rejeitar a substituição do run existente.

```bash
FORCE=1 bundle exec rake sources:update  # descarregar ambas as fontes novamente
FORCE=1 bundle exec rake refresh         # descarregar → analisar → construir site
bundle exec rake rebuild                # analisar → construir site; sem downloads
```

`rebuild`, `analysis:local`, `analysis:public` e `site:build` não consultam `FORCE` e nunca descarregam fontes.

O modo público cria o run em:

```text
data/snapshots/<airbnb-snapshot-date>__<official-download-date>/
```

Existe uma pasta pública por par de datas. Uma reanálise valida os novos outputs antes de substituir essa pasta e as suas linhas históricas. Os outros pares de datas permanecem iguais; o Git conserva as versões anteriormente commitadas. Os runs locais continuam imutáveis.

Cada novo run público contém apenas:

- `snapshot.json` — documento agregado autoritativo, com schema 6.0.0;
- `report.html` — relatório autónomo em português.

O PDF é uma derivação opcional do relatório. CSV e JSON separados não são
gerados nem publicados nos novos runs. Datas, URLs, hashes e versões ficam no
campo `metadata` do documento; resumo, grupos, anúncios por freguesia e
classificação, totais por freguesia e métricas de registo estão no mesmo ficheiro.

Para regenerar apenas o relatório de um snapshot existente, execute
`bundle exec ruby scripts/regenerate_public_report.rb data/snapshots/<run_id>`.
O script reutiliza as métricas de registo guardadas, valida-as e verifica a
proveniência e os totais municipais antes de substituir `report.html`. Não
descarrega fontes nem recalcula a análise. Snapshots sem métricas compatíveis
exigem reanálise; a regeneração falha sem alterar o relatório existente. Um PDF
existente não é atualizado por este comando.

A regeneração e a construção do site usam `PublicSnapshot::Loader`, também
usado para validar os outputs antes da publicação de uma análise. Nos novos
runs, `snapshot.json` é a única fonte de verdade. O documento tem
`schema_version` 6.0.0 e os campos `metadata`, `summary`,
`licence_group_aggregates`, `announcements_by_parish_and_classification`,
`parish_totals` e `registration_metrics`. O loader mantém a mesma interface
imutável, com chaves string, independentemente do armazenamento.

A regeneração do relatório e o site leem exclusivamente `snapshot.json` nos runs consolidados.
A publicação valida o documento, a proveniência e a coerência dos agregados.
Cada análise pública recalcula os resultados e gera `snapshot.json` e
`report.html`. Antes de substituir um par já publicado, verifica os hashes
das fontes existentes e valida os novos outputs.
Um documento inválido ou de versão incompatível faz a leitura falhar; nunca
se tenta reconstruí-lo de ficheiros separados.

Para compatibilidade, o loader lê documentos do schema 5.0.0 sem depender das
suas antigas exportações. Também lê os ficheiros separados do schema 4.0.0,
com métricas 1.0.0 e metodologias 2.0.0/2.1.0, adaptando-os antes da mesma
validação. Runs antigos sem métricas suportadas podem permanecer no arquivo;
a seleção do site conserva essa compatibilidade. Uma reanálise com fontes
datadas e hashes verificados substitui apenas o par escolhido pelo formato
atual. A leitura de um formato anterior não evita a reanálise. O formato
dos outputs locais mantém-se.

Nos agregados, as contagens são inteiros: `announcements` conta anúncios,
`announcements_with_identifiable_number` conta anúncios com número identificável
e `estimated_establishments` é uma estimativa. `licence_groups` conta grupos de
números identificáveis; `spatial_locations` conta clusters espaciais. Os
conjuntos de números distintos estão apenas nas métricas de registo. Metadata
e resumo conservam os campos JSON publicados. As estimativas e os números
distintos da cidade não são somas de freguesias. A interface do loader
preserva os resultados analíticos para o site e o relatório.

O arquivo público foi reduzido a dois pares de fontes arquivadas, reanalisados
com metodologia 2.1.0 e análise 3.4.0, após verificar os SHA-256 contra o manifesto
do backup. Os rótulos trimestrais são rótulos do arquivo, não datas de recolha:

| Arquivo | Airbnb | Download RNAL | Run |
| --- | --- | --- | --- |
| Q4 2025 | 2025-09-21 | 2025-11-25 | `2025-09-21__2025-11-25` |
| Q3 2026 | 2026-06-23 | 2026-09-26 | `2026-06-23__2026-09-26` |

Os runs de desenvolvimento dos restantes pares e as respetivas linhas de
histórico foram removidos da árvore atual. As versões commitadas continuam
recuperáveis pelo Git; as fontes locais e os backups foram preservados.

O histórico público em `data/history/summary.csv` mantém uma linha atual por par de datas. O gráfico de distâncias do site usa `data/history/distance_ranges.csv`: cada run público novo acrescenta quatro contagens agregadas de números de licença, sem coordenadas nem números de licença individuais. Para preencher este agregado num run público anterior sem alterar o snapshot, use `bundle exec ruby scripts/backfill_distance_ranges.rb <run_id>` com os ficheiros fonte originais; o script verifica os hashes do metadata antes de escrever. Uma reanálise substitui apenas as linhas históricas do mesmo par de datas, incluindo os agregados de distâncias e regiões. Para gerar também um PDF derivado, instale `wkhtmltopdf` ou `weasyprint` e execute:

```bash
GENERATE_PDF=1 bundle exec rake analysis:public
GENERATE_PDF=1 bundle exec rake analysis:local
```

O PDF chama-se `report.pdf` nos dois modos. No modo público deriva de
`report.html`; no modo local, de `report_local.html`. O writer tenta
`wkhtmltopdf` e, se necessário, `weasyprint`.

### Organização da análise

`Analysis.run` descreve a sequência: preparar fontes e destino, calcular o
resultado, gerar dados e relatório, gerar o PDF se pedido e publicar. Recebe
os dois caminhos de fontes ou nenhum, o modo e as opções de destino/PDF;
devolve `{run_id:, path:, summary:}`. Sem caminhos explícitos, seleciona o par
local datado mais recente. Não existe uma classe `Runner` separada.

As responsabilidades estão em objetos e módulos de `Analysis`:

| Componente | Responsabilidade |
| --- | --- |
| `PreparedSources::Pair` | Seleção e preparação das fontes, datas, URLs, hashes, verificação dos bytes e identificador do par |
| `Classifier` | Linhas detalhadas com correspondências e classificações |
| `Aggregates`, `AnnouncementCounts`, `RegistrationMetrics` | Agregados de anúncios, grupos, freguesias e métricas de conjuntos |
| `Result` | Resultado calculado, resumo, metadata e construção do `PublicSnapshot` validado |
| `OutputWriter` | Escrita dos dados, relatório HTML e PDF opcional a partir de um resultado e destino |
| `History` | Comparações e linhas históricas |
| `PublicPublisher` | Staging, validação, instalação conjunta do snapshot e histórico, rollback e limpeza |

O identificador base pertence ao par de fontes. O sufixo dos reruns locais
depende dos diretórios existentes e é decidido pela análise. O metadata junta
a proveniência das fontes à identificação e versões do run e à proveniência
Git. `official_register_date` é a maior data de registo entre as linhas
oficiais correspondentes aos anúncios classificados; não é a data de download
do RNAL, guardada separadamente em `official_register_download_date`.

A reorganização preserva metodologia, schema, agregados e os outputs da
fixture sintética. Scripts e testes específicos usam diretamente o componente
responsável; `Analysis` mantém apenas `run` como interface pública.

Os relatórios ainda são montados por `Report` em Ruby durante a análise. A
migração para templates Jekyll partilhados entre o site e um build de relatório
isolado está planeada em [TODO.md](TODO.md).

## Site público

O site estático publicável é montado a partir dos snapshots e do histórico agregado já versionados:

```bash
npm ci
bundle exec rake site:build
```

As tarefas do projeto são executadas pelo Rake; npm fornece as ferramentas
frontend, incluindo a compilação de CSS. `bundle exec rake` continua a executar
os testes por defeito. As tarefas carregam apenas o código necessário e chamam
`Analysis.run`, `SiteBuilder` e `SiteChecker` em Ruby. O build do site usa os snapshots
públicos existentes; não executa a análise nem descarrega fontes.

Scripts e testes carregam `lib/alojamento_local.rb`; o Zeitwerk carrega as
classes e módulos conforme os caminhos em `lib/alojamento_local/`. O teste
de carregamento antecipado em `test/alojamento_local_test.rb` verifica essa
correspondência.

`site:build` prepara os dados do Jekyll, gera as páginas, compila o CSS,
verifica a estrutura e executa a auditoria de publicação do artefacto. Para
repetir apenas as etapas de CSS ou verificação:

```bash
npm run site:css
bundle exec rake site:check
ruby scripts/audit_publication.rb --artifact _site
```

Os templates HTML/Liquid em `site/` usam Prettier com o plugin Liquid,
indentação de dois espaços e largura preferida de 100 caracteres. Para formatar
ou verificar a formatação sem alterar ficheiros:

```bash
npm run site:format
npm run site:lint
```

A verificação corre em CI nos pushes, pull requests e builds de publicação.
Formate os ficheiros fonte; os snapshots arquivados e `_site/` ficam fora deste
comando. A largura é uma preferência: valores de atributos indivisíveis podem
continuar numa linha mais longa.

O CSS editável está em `site/assets/css/`: `input.css` importa os tokens e
estilos existentes. Prefira classes Tailwind e os tokens do projeto nas alterações
ao site. O CSS gerado fica em `_site/assets/story.css`; `_site/` não é fonte
editável, e Jekyll não publica os ficheiros CSS de origem.

O hook `site/_plugins/tailwind.rb` compila o CSS com Node/Tailwind depois de
Jekyll escrever as páginas. Assim, `bundle exec jekyll build` e os rebuilds de
`bundle exec jekyll serve` também geram o CSS no destino configurado. É necessário
ter Node e as dependências de `npm ci` instalados; uma falha na compilação faz
falhar o build. `npm run site:css` continua disponível para compilar apenas o CSS.

O resultado fica em `_site/` e inclui as páginas editoriais e de freguesias,
`snapshot.json`, relatórios HTML, PDFs existentes, licença e avisos de atribuição.
As exportações agregadas de snapshots legados mantêm os seus caminhos antigos.
Os relatórios são copiados para `_site/runs/<run_id>/`, sem regeneração de HTML
ou PDF e sem alterar snapshots versionados. Datasets brutos,
resultados locais e caches não são copiados. O diretório `_site/` pode ser usado
como artefacto de um deployment estático. O workflow mensal constrói e
valida esse diretório antes de o publicar no GitHub Pages.

O site é mantido como um projeto Jekyll em `site/`: layouts e includes
partilham a estrutura HTML, as páginas Liquid tratam a narrativa editorial e
`AlojamentoLocal::SiteBuilder` prepara os dados públicos e chama Jekyll através
da tarefa `site:build`.

Para rever alterações localmente, construa o artefacto e sirva `_site/`:

```bash
bundle exec rake site:build
python3 -m http.server 4000 --directory _site
```

Abra `http://localhost:4000`. Depois de editar apenas CSS, execute
`npm run site:css` e atualize a página. Depois de editar templates ou dados,
execute `bundle exec rake site:build` e atualize a página.

Para rever a homepage em desktop, tablet e telemóvel:

```bash
bundle exec rake site:screenshots
```

O comando constrói o site e usa Playwright com o Chrome instalado para guardar
capturas a 1440, 768 e 390 px em `tmp/screenshots/`. Defina `CHROME_BIN` se
precisar de outro executável Chromium. O comando falha se houver deslocamento
horizontal. Verifique também o foco por teclado, os links e as restantes páginas
num browser local.

Para capturar outras páginas, passe o caminho à tarefa (as aspas protegem os
parênteses retos na shell):

```bash
bundle exec rake 'site:screenshots[freguesias/arroios/index.html]'
bundle exec rake 'site:screenshots[metodologia.html]'
```

As capturas recebem o nome da página, por exemplo
`tmp/screenshots/freguesias-arroios-390.png`.

Os diagramas de sobreposição e os números RNAL nas páginas de freguesia usam
métricas agregadas e versionadas. Ver [métricas de registo](#métricas-de-registo)
para as definições e limitações.
O trabalho a retomar em futuras sessões está em [TODO.md](TODO.md).

O workflow de GitHub Pages define automaticamente a base `/alojamento-local-em-analise`.

## Testes

```bash
bundle exec rake test
```

O comando descobre todos os ficheiros `test/**/*_test.rb`, incluindo a regressão
completa do pipeline com fontes sintéticas e outputs esperados em Git.
Também verifica a preparação única das fontes, a separação das tarefas,
os guards de hashes, os reruns locais e o rollback da publicação após falha
ou interrupção. Os testes de PDF usam conversores simulados para verificar
o HTML de origem nos dois modos, o fallback e o destino do ficheiro derivado.
`bundle exec rake` executa a mesma tarefa por omissão. Para executar só a regressão:

```bash
bundle exec rake test TEST=test/pipeline_regression_test.rb
```

Ver [casos e atualização dos outputs esperados](test/fixtures/pipeline/README.md).

Antes de publicar ou rever alterações aos outputs, execute a auditoria de publicação:

```bash
ruby scripts/audit_publication.rb
ruby scripts/audit_publication.rb --history
```

O primeiro comando verifica os ficheiros publicáveis na árvore atual; o segundo verifica todos os commits e refs alcançáveis.

## GitHub Actions

`.github/workflows/monthly-analysis.yml` executa no dia 1 de cada mês, às 07:00 UTC, ou manualmente. Depois dos testes, restaura o artefacto `analysis-sources` da última execução bem-sucedida com fontes ainda disponíveis no ramo principal. Executa `sources:update`, guarda apenas o par datado selecionado num novo artefacto e chama `analysis:public`. Regista os outputs públicos versionados no repositório e constrói o site com `site:build` antes de o publicar.

O artefacto das fontes tem retenção de 90 dias e é novamente carregado em cada execução mensal, mesmo quando o par não muda. Se não existir um artefacto disponível, o workflow descarrega as fontes atuais. Não é um arquivo permanente: uma pausa superior à retenção pode perder as fontes de um run antigo. Para preparar manualmente apenas o par local para este artefacto, use `bundle exec rake sources:archive` (`tmp/source-artifact/`).

Para reutilizar localmente as fontes de uma execução Actions, descarregue o
artefacto sem alterar nomes ou datas (com GitHub CLI autenticado):

```bash
gh run download <run-id-actions> --name analysis-sources --dir data_sources
bundle exec rake rebuild
```

`.github/workflows/publication-audit.yml` executa automaticamente a verificação de segurança dos outputs em pushes e pull requests.

O repositório pode permanecer privado enquanto um deployment separado publica o
conteúdo sanitizado de `_site/`.

O workflow mensal faz commit apenas dos outputs públicos sanitizados em `data/snapshots/` e `data/history/`; o site é publicado como artefacto separado através do GitHub Pages, depois de executar testes, construir o site e passar os gates de publicação. Os snapshots commitados e o histórico são a fonte permanente do projeto. Datasets brutos em `data_sources/`, resultados detalhados em `data/private/` e caches em `tmp/` continuam fora do Git por defeito. Os documentos atuais e os CSVs legados dos snapshots são agregados e não contêm identificadores de anúncios, anfitriões, nomes, endereços, coordenadas ou valores de licença individuais.

O workflow `.github/workflows/site-publish.yml` reconstrói e publica o site em pushes humanos para `main` e através de `workflow_dispatch`. Está protegido contra o commit `Atualiza análise mensal` produzido pelo workflow mensal, que já constrói e publica o site na própria execução.

## Dados e método

As fontes são o arquivo público [Inside Airbnb](https://insideairbnb.com/get-the-data/) e o registo oficial disponibilizado pelo Turismo de Portugal. Na etapa `sources:update`, o downloader descobre na página do Inside Airbnb o snapshot mais recente disponível para Lisboa; `last_scraped` é uma data ao nível do anúncio e pode abranger vários dias.

As licenças são normalizadas de forma conservadora. O analisador distingue, entre outras categorias:

- licença/listagem única;
- provável estabelecimento com múltiplos quartos ou unidades;
- licença repetida na mesma localização;
- mesma licença em várias localizações;
- licença oficial fora de Lisboa;
- campo de licença vazio;
- valor de licença não identificável como AL.

`host_id` pode ser usado apenas durante a análise local como metadado, nunca como critério de agrupamento; não é escrito nos outputs públicos. A estimativa de estabelecimentos colapsa apenas categorias de menor risco e mantém casos de possível reutilização separados para verificação.

O campo `identifiable_licences` dos CSVs conta anúncios com um número AL
identificável, não números distintos nem correspondências confirmadas no RNAL.
A categoria “licença única em Lisboa” exige um único anúncio
e uma correspondência no RNAL com concelho Lisboa; não confirma validade ou atividade do registo.

### Métricas de registo

`registration_metrics` em `snapshot.json` (métricas 1.0.0, schema público 6.0.0)
contém Lisboa,
as 24 freguesias e um agregado de geografia não identificada. As definições
completas também acompanham cada ficheiro no campo `definitions`.

| Campos | O que contam |
| --- | --- |
| `rnal`, `airbnb` | Números AL normalizados distintos no conjunto local de cada fonte |
| `intersection`, `rnal_only`, `airbnb_only` | Interseção e diferenças dos conjuntos locais |
| `another_lisbon_parish`, `another_municipality`, `no_national_match`, `unresolved_official_geography` | Partição de `airbnb_only`: outra freguesia de Lisboa, outro município, ausência no RNAL nacional ou geografia oficial por resolver |
| `announcements` | Anúncios observados cujo município normaliza para Lisboa |
| `empty_licence`, `unrecognised_licence`, `identifiable_number` | Partição dos anúncios: campo vazio, preenchido não reconhecido ou número AL identificável |
| `confirmed_rnal_match` | Anúncios com número encontrado no RNAL nacional datado; subconjunto de `identifiable_number` |
| `official_entries` | Linhas oficiais de Lisboa, incluindo duplicados |

O RNAL usa concelho/freguesia oficiais; o Airbnb usa a geografia observada.
Normalizam-se espaços, maiúsculas e acentos, com aliases explícitos para as
grafias Airbnb de freguesias que perderam letras acentuadas. Freguesias
desconhecidas entram no total municipal e num agregado próprio, cuja interseção
é zero. O total de números distintos de Lisboa é calculado diretamente; nunca
se obtém somando freguesias.

“Só RNAL” significa ausência no Airbnb da mesma geografia; “só Airbnb” não
significa ausência no RNAL nacional. Registos oficiais com geografia ausente ou
conflituante ficam por resolver. Uma correspondência não confirma validade,
atividade ou localização real. As áreas dos círculos e a interseção usam os
conjuntos medidos; a bolha de anúncios sem número identificável usa uma escala
separada. Diagramas diferentes não têm uma escala comum.

Os agrupamentos espaciais são componentes conexas de ligações até 500 m:
extremos ligados por uma cadeia podem estar mais afastados. Coordenadas ausentes
permanecem em grupos individuais. A estimativa colapsa apenas grupos na mesma
localização com correspondência oficial Lisboa, classificados como provável
estabelecimento múltiplo ou repetição na mesma localização. Mantém os restantes
anúncios separados e calcula cada geografia independentemente; estimativas de
freguesias também não devem ser somadas para obter Lisboa.

Para recalcular um par de fontes já guardado, verificando os hashes originais:

```bash
bundle exec ruby scripts/reanalyse_public_run.rb <run_id>
```

### Versão da metodologia

Cada run regista `methodology_version`, versões de análise/schema, datas e hashes
das fontes e proveniência Git. O relatório identifica a metodologia. O sistema
atual compara apenas runs com metodologia idêntica; a simplificação para o
primeiro lançamento e o arquivo de fontes estão planeados em [TODO.md](TODO.md).

**2.1.0 (análise 3.2.0):** um único filtro normalizado de município Airbnb
alimenta classificação, métricas e reutilização. Antes, variantes como ` Lisboa `
e `lisboa` contavam para reutilização mas eram excluídas dos resultados. Na
fixture sintética, os anúncios passam de 32 para 34 e a estimativa mantém-se em
28. Com as mesmas fontes de `2026-06-23__2026-09-26`, grupos e métricas completos
mantêm-se iguais: 17 064 anúncios e estimativa de 14 600. Outros arquivos podem
ter impacto diferente. Os dois pares do arquivo público foram posteriormente
reanalisados com esta metodologia; as versões e fontes estão no metadata.

**Análise 3.3.0 / schema público 5.0.0:** consolida os agregados em
`snapshot.json`, mantendo metodologia 2.1.0 e métricas 1.0.0. Os leitores dos
formatos anterior e atual produzem os mesmos dados do site e relatórios para
os mesmos agregados, exceto a identificação das versões. Na fixture sintética,
conservam-se 34 anúncios, 18 grupos de números, 19 entradas oficiais de Lisboa
e estimativa de 28 estabelecimentos. A reanálise das mesmas fontes de Q3 2026
mantém os resultados completos, verificados contra o snapshot anterior.

**Análise 3.4.0 / schema público 6.0.0:** elimina as exportações CSV/JSON dos
runs públicos. Cada run guarda apenas o documento de dados e o relatório HTML,
com PDF opcional. Links e referências apontam para `snapshot.json`; a estrutura
dos agregados, a metodologia e as métricas permanecem iguais. A fixture
sintética conserva todos os resultados, e os dois runs arquivados foram
regenerados com as mesmas fontes verificadas, sem mudanças nos agregados.

### Exemplos de sinais

O relatório inclui uma secção de exemplos ilustrativos, baseada em padrões sintéticos dos testes, para explicar a leitura das classificações sem expor casos individuais. Abrange ausência de licença identificável, possíveis anúncios múltiplos do mesmo estabelecimento, repetição de licença em localizações distintas, registo oficial fora de Lisboa e possível divergência de localização.

Estes exemplos não contêm números reais de licença, nomes, IDs, URLs, endereços, coordenadas ou distâncias exatas. Os resultados publicados são agregados ao nível de freguesia/classificação e devem ser tratados como indicadores para verificação, nunca como conclusões legais.

Para instruções de manutenção e interpretação, consulte [`AGENTS.md`](AGENTS.md).
