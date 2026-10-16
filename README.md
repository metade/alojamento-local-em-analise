# Alojamento Local em Lisboa — indicadores para verificação

Análise investigativa de snapshots de anúncios Airbnb em Lisboa comparados com o registo oficial português de alojamento local. Os resultados são indicadores para verificação oficial, não conclusões jurídicas.

## Execução

```bash
bundle install
bundle exec rake sources:update
bundle exec rake analysis
bundle exec jekyll serve
```

Há uma única análise, sem modos ou flags de diagnóstico. Cada execução recalcula
as fontes datadas locais e produz dois conjuntos separados:

| Destino | Conteúdo | Git / publicação |
| --- | --- | --- |
| `data/snapshots/<airbnb-date>__<rnal-download-date>/` | `snapshot.json` agregado e relatórios públicos arquivados, quando existentes | Versionado |
| `data/private/<airbnb-date>__<rnal-download-date>/` | Dois CSVs de diagnóstico | Ignorado, nunca publicado |

Os diagnósticos incluem nomes, licenças originais, identificadores, endereços
e coordenadas. O snapshot nunca recebe esses campos. A análise escreve apenas
dados. O Jekyll gera os relatórios público e privado a partir da mesma página
`site/report.html`: o privado acrescenta as tabelas dos CSVs. Ambos têm HTML
completo e PDF; os CSVs detalhados acompanham apenas o relatório privado.

Atualizar fontes, analisar e construir o site são etapas independentes:

```bash
bundle exec rake sources:update   # verifica fontes remotas e descarrega se necessário
bundle exec rake analysis         # snapshot agregado + diagnósticos privados, sem rede
bundle exec rake site:build       # site e relatórios públicos HTML/PDF
bundle exec jekyll serve          # build e observação + servidor local com links privados
bundle exec rake refresh          # atualizar fontes → análise → site público
bundle exec rake rebuild          # análise → site público; sem downloads
```

`sources:update` consulta o índice Inside Airbnb para Lisboa e descarrega um CSV
em falta. Reutiliza o RNAL datado mais recente se a sua data de download for igual
ou posterior à data do snapshot Airbnb; caso contrário, descarrega uma cópia com
a data real de hoje. Nunca altera a data de uma cópia existente.

A análise sem argumentos seleciona o par datado mais recente em `data_sources/`,
sem rede. Para reproduzir um par anterior, use `bundle exec rake 'analysis[<run_id>]'`.
A tarefa carrega e valida o snapshot existente, seleciona as fontes locais datadas
pelo metadata e verifica ambos os hashes SHA-256 antes de recalcular com as versões
atuais. IDs inválidos ou desconhecidos, fontes em falta e hashes diferentes são
rejeitados antes da análise, sem substituir os resultados existentes.

Cada par tem um identificador baseado apenas nas duas datas. Reanalisar substitui
o snapshot, os diagnósticos e as linhas desse par no histórico após validação,
com staging e rollback em conjunto. Os restantes pares ficam iguais; o Git
conserva versões anteriores dos agregados. Não há IDs de rerun, histórico privado,
reutilização de resultados ou modos local/público. Fontes com hashes diferentes
para um par já publicado continuam a ser rejeitadas.

`FORCE=1` aplica-se apenas a `sources:update`, incluindo a etapa de fontes de
`refresh`. Volta a descarregar ambas as fontes. `analysis`, `rebuild` e
`site:build` nunca descarregam fontes, mesmo com `FORCE=1`.

### Snapshots e relatórios

O documento autoritativo `snapshot.json` usa schema 7.0.0, sem campo `mode`.
Os `report.html`/`report.pdf` já arquivados nas pastas dos snapshots são
preservados por reanálises. São artefactos históricos; o site gera relatórios
novos a partir do snapshot e não usa essas cópias. A análise continua a escrever
apenas dados, sem gerar ou atualizar os relatórios arquivados.
`PublicSnapshot.load` devolve um Hash com chaves string. JSON Schema verifica
estrutura e tipos; Ruby verifica proveniência e contabilidade. Não há leitores
legados ou fallback: formatos anteriores exigem reanálise de fontes verificadas.

O documento contém `metadata`, `summary`, `licence_group_aggregates`,
`announcements_by_parish_and_classification`, `parish_totals` e
`registration_metrics`. Datas, URLs, hashes SHA-256, versões e proveniência Git
ficam registados. Contagens de anúncios e entradas oficiais são distintas dos
conjuntos de números normalizados; as estimativas municipais e os números
distintos não são somas de freguesias.

A análise 3.7.0 remove os modos e escreve sempre os diagnósticos separadamente.
A metodologia mantém-se em 2.1.0: a fixture sintética e os dois pares arquivados
foram recalculados com os mesmos bytes verificados, sem alterações aos valores
analíticos. O arquivo conserva os pares `2025-09-21__2025-11-25` (Q4 2025) e
`2026-06-23__2026-09-26` (Q3 2026); os rótulos trimestrais não são datas de recolha.
O histórico agregado em `data/history/` continua a manter uma linha de resumo
e as contagens auxiliares atuais por par.

Para construir apenas um relatório público, sem análise ou downloads:

```bash
bundle exec rake 'report:build[data/snapshots/<run_id>]'
```

O destino por omissão é `tmp/reports/<run_id>/`, substituível por `DESTINATION`.
Deve ser separado do snapshot de entrada. O Jekyll usa a página completa
`site/report.html`, com CSS incorporado e `layout: null`, tanto no site como no
build autónomo. Após escrever HTML, `ReportPdf` gera `report.pdf` com o
`wkhtmltopdf-binary` incluído no bundle. Em Ubuntu são necessárias `libxrender1`,
`libfontconfig1`, `libxext6` e fontes. Não há conversor alternativo.
Os builds não alteram snapshots ou históricos; uma falha pode deixar o destino
incompleto e exige repetir o build. O site publica apenas os ficheiros permitidos
em `_site/runs/<run_id>/`.

### Organização da análise

`Analysis.run` prepara fontes e destinos, calcula e publica o resultado. Devolve
`{run_id:, path:, private_path:, summary:}`. As opções de destino são
`output_root`, `history_path` e `private_root`; os destinos privados têm de ficar
separados dos snapshots, histórico e diretórios do site.

| Componente | Responsabilidade |
| --- | --- |
| `PreparedSources::Pair` | Preparação única das fontes, datas, URLs, hashes e verificação dos bytes |
| `Classifier` | Linhas detalhadas e classificações |
| `Aggregates`, `AnnouncementCounts`, `RegistrationMetrics` | Contagens, estimativas e conjuntos medidos |
| `Result` | Resultado, metadata e snapshot agregado validado |
| `OutputWriter` | Snapshot ou diagnósticos em destinos separados |
| `History` | Comparações e CSVs históricos agregados |
| `PublicPublisher` | Validação, instalação conjunta de snapshot/diagnósticos/histórico e rollback |
| Gerador de relatórios Jekyll | Template partilhado para relatórios públicos e, ao servir localmente, privados |

`official_register_date` é a maior data de registo entre as linhas oficiais
correspondentes aos anúncios; `official_register_download_date` é a data da
cópia RNAL utilizada. Scripts e testes usam diretamente o componente responsável.

## Site público

O site estático publicável é montado a partir dos snapshots e do histórico agregado já versionados:

```bash
npm ci
bundle exec rake site:build
```

As tarefas do projeto são executadas pelo Rake; npm fornece as ferramentas
frontend, incluindo a compilação de CSS. `bundle exec rake` continua a executar
os testes por defeito. As tarefas carregam apenas o código necessário e chamam
`Analysis.run` e `SiteChecker` em Ruby e `jekyll build` pela CLI. O build do site usa os snapshots
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

`site:check` verifica os ficheiros gerados e links para relatórios e downloads.
O Jekyll verifica a sintaxe Liquid. A auditoria de publicação valida os dados e
a privacidade; os testes do relatório verificam cálculos, escaping, defaults
históricos e renderização equivalente entre os modos de build.

O resultado fica em `_site/` e inclui as páginas editoriais e de freguesias,
`snapshot.json`, relatórios HTML e PDFs gerados, licença e avisos de atribuição.
O build gera os relatórios em `_site/runs/<run_id>/`, primeiro o HTML e depois
o PDF, sem alterar snapshots versionados. Datasets brutos,
resultados locais e caches não são copiados. O diretório `_site/` pode ser usado
como artefacto de um deployment estático. O workflow mensal constrói e
valida esse diretório antes de o publicar no GitHub Pages.

O site é mantido como um projeto Jekyll em `site/`: layouts e includes
partilham a estrutura HTML, as páginas Liquid tratam a narrativa editorial e
os plugins preparam os dados públicos e os relatórios através dos geradores e
hooks normais do Jekyll. `bundle exec jekyll build` também gera os downloads,
CSS e PDFs; `site:build` acrescenta as verificações e a auditoria de publicação.

Para rever o site com os relatórios privados disponíveis:

```bash
bundle exec jekyll serve
```

Abra `http://127.0.0.1:4000` (`--port` altera a porta). O Jekyll ativa
`site.config["serving"]`: o gerador inclui os relatórios privados quando existem
os dois CSVs do par de datas. O layout mostra o link «Relatório detalhado · uso
local». O HTML/PDF, snapshot agregado e CSVs ficam em
`_site/private-reports/<run_id>/`.

Na secção «Grupos de licenças», o relatório apresenta apenas casos para
verificação: omite licenças únicas em Lisboa, prováveis estabelecimentos com
anúncios múltiplos e repetições na mesma localização. Os CSVs descarregáveis
mantêm todas as linhas; a tabela de anúncios mantém os detalhes completos.

O build local contém dados privados e permanece ignorado pelo Git. Um
`jekyll build` normal, incluindo `site:build` e os workflows GitHub Actions,
exclui os relatórios privados e remove os ficheiros deixados por um build local
no mesmo destino. A auditoria rejeita a publicação de um build com dados ou
links privados. Não há flag específico para GitHub Actions, servidor adicional
ou alteração das respostas HTTP.

O Jekyll observa alterações nos templates e reconstrói o site. Atualize a página
para ver o resultado, ou use `--livereload`. Depois de reanalisar fontes fora da
pasta `site/`, reinicie o servidor para regenerar os relatórios.

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
os guards de hashes, o preview privado e o rollback da publicação após falha
ou interrupção. Os testes de PDF usam conversores simulados para verificar
o HTML de origem, falhas de conversão e o destino do ficheiro derivado.
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

`.github/workflows/monthly-analysis.yml` executa no dia 1 de cada mês, às 07:00 UTC, ou manualmente. Depois dos testes, restaura o artefacto `analysis-sources` da última execução bem-sucedida com fontes ainda disponíveis no ramo principal. Executa `sources:update`, guarda apenas o par datado selecionado num novo artefacto e chama `analysis`. Regista os outputs públicos versionados no repositório e constrói o site com `site:build` antes de o publicar.

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

O workflow mensal faz commit apenas dos outputs públicos sanitizados em `data/snapshots/` e `data/history/`; o site é publicado como artefacto separado através do GitHub Pages, depois de executar testes, construir o site e passar os gates de publicação. Os snapshots commitados e o histórico são a fonte permanente do projeto. Datasets brutos em `data_sources/`, resultados detalhados em `data/private/` e caches em `tmp/` continuam fora do Git por defeito. Os documentos dos snapshots são agregados e não contêm identificadores de anúncios, anfitriões, nomes, endereços, coordenadas ou valores de licença individuais.

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

`host_id` pode ser usado apenas nos diagnósticos privados da análise como metadado, nunca como critério de agrupamento; não é escrito nos outputs públicos. A estimativa de estabelecimentos colapsa apenas categorias de menor risco e mantém casos de possível reutilização separados para verificação.

A categoria “licença única em Lisboa” exige um único anúncio
e uma correspondência no RNAL com concelho Lisboa; não confirma validade ou atividade do registo.

### Métricas de registo

`registration_metrics` em `snapshot.json` (métricas 1.0.0, schema público 7.0.0)
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
bundle exec rake 'analysis[2026-06-23__2026-09-26]'
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

**Análise 3.4.0 / schema público 7.0.0:** elimina as exportações CSV/JSON dos
runs públicos. Cada run guarda apenas o documento de dados e o relatório HTML,
com PDF opcional. Links e referências apontam para `snapshot.json`; a estrutura
dos agregados, a metodologia e as métricas permanecem iguais. A fixture
sintética conserva todos os resultados, e os dois runs arquivados foram
regenerados com as mesmas fontes verificadas, sem mudanças nos agregados.

### Exemplos de sinais

O relatório inclui uma secção de exemplos ilustrativos, baseada em padrões sintéticos dos testes, para explicar a leitura das classificações sem expor casos individuais. Abrange ausência de licença identificável, possíveis anúncios múltiplos do mesmo estabelecimento, repetição de licença em localizações distintas, registo oficial fora de Lisboa e possível divergência de localização.

Estes exemplos não contêm números reais de licença, nomes, IDs, URLs, endereços, coordenadas ou distâncias exatas. Os resultados publicados são agregados ao nível de freguesia/classificação e devem ser tratados como indicadores para verificação, nunca como conclusões legais.

Para instruções de manutenção e interpretação, consulte [`AGENTS.md`](AGENTS.md).
