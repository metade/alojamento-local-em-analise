# AL em análise

Este projeto compara anúncios Airbnb em Lisboa com o Registo Nacional de
Alojamento Local (RNAL). Os resultados são indicadores para verificação, não
conclusões legais sobre a ilegalidade de anúncios ou estabelecimentos.

## Executar

```bash
bundle install
npm ci
bundle exec rake sources:register  # proveniência dos CSVs locais, sem rede
bundle exec rake analysis          # recalcula o último par local, sem rede
DESTINATION=tmp/candidate-site bundle exec rake site:build
```

`analysis` escreve exatamente `summary.json` e `candidates.json.gz` em
`data/snapshots/<data-arquivo-airbnb>__<data-ficheiro-rnal>/`
como único output da análise. Não são gerados diagnósticos nem outputs privados.
Reanalisar substitui esse snapshot. Outros pares permanecem intactos. Não existem comparações
históricas, versões de output, leitores de formatos antigos ou fallback.

O build seleciona a pasta datada mais recente. Valida o documento selecionado e
falha se estiver ausente ou inválido. `SNAPSHOT=/caminho/para/pasta` seleciona outro
snapshot explicitamente. A fixture inventada de apresentação continua disponível:

```bash
SNAPSHOT=test/fixtures/pipeline/snapshots/candidate DESTINATION=tmp/fixture-site bundle exec rake site:build
DESTINATION=tmp/candidate-report bundle exec rake 'report:build[data/snapshots/2026-06-23__2026-09-26]'
```

O site publica `/snapshots/<pasta-selecionada>/summary.json` e
`/snapshots/<pasta-selecionada>/candidates.json.gz`, `/report.html` e
`/report.pdf`. Há um único relatório, comum ao site, ao servidor local e ao build autónomo,
com o mesmo template e os mesmos cálculos. Não existe um relatório privado.
Builds não executam análise nem alteram as fontes ou snapshots. O Jekyll remove
outputs antigos de destinos reutilizados; builds normais não contêm relatórios
privados nem rotas antigas `runs/`.

A tabela detalhada dos relatórios omite candidatos sem sinais nem revisão de
agrupamento, com número encontrado no RNAL em Lisboa, freguesias atribuída, por
coordenadas e oficial concordantes e distância conhecida até 500 m. Casos por
resolver permanecem visíveis. Totais, gráficos e downloads incluem todos os
candidatos; a omissão não é uma certificação legal.

## Fontes e proveniência

- Airbnb: [Inside Airbnb](https://insideairbnb.com/get-the-data/), arquivo de Lisboa.
- RNAL: [Turismo de Portugal / ArcGIS](https://hub.arcgis.com/api/download/v1/items/4e62eb1977564991bd01e61d7aa8266f/csv?redirect=false&layers=6).
- Limites: [Câmara Municipal de Lisboa](https://gisapps.cm-lisboa.pt/arcgis/rest/services/SGPI_Open/LXSGPI_Temas/MapServer/4).

`data_sources/` conserva CSVs datados e manifestos `*.csv.manifest.json`, ignorados
pelo Git. Cada manifesto guarda URL, nome, SHA-256, data do ficheiro, data do
arquivo Airbnb e data de download quando documentada. `sources:register` regista
os CSVs datados existentes offline. Datas de download desconhecidas ficam `null`:
nunca são inferidas de mtime, `last_scraped`, backups ou da data atual.

`source_dates.airbnb_snapshot_date` é obrigatória e identifica o arquivo Airbnb.
`airbnb_fetched_on` e `rnal_fetched_on` podem ser `null`. A data no nome do ficheiro
RNAL identifica a fonte selecionada, sem estabelecer uma data de download.

```bash
bundle exec rake sources:update   # rede explícita: verificar arquivo e atualizar quando necessário
bundle exec rake sources:archive  # apenas o par local selecionado e os seus manifestos
bundle exec rake rebuild          # análise local + site
bundle exec rake refresh          # atualização de fontes + análise + site
```

Downloads futuros bem-sucedidos registam a data real de download. A reutilização
de cache e os artefactos CI preservam os manifestos. `FORCE=1` só afeta a atualização.
Fontes históricas podem ser escolhidas em Ruby com ambos os caminhos explícitos:

```ruby
require_relative "lib/alojamento_local"
AlojamentoLocal::Analysis.run(
  airbnb_path: "data_sources/listings-2026-06-23.csv",
  official_path: "data_sources/Estabelecimentos_de_Alojamento_Local-2026-09-26.csv"
)
```

Não há argumento `analysis[run_id]`. `output_root` permite isolar os snapshots.
Os manifestos de proveniência permanecem junto dos CSVs em `data_sources/`.

## Contrato e unidades

`schema/candidate_summary.schema.json` e `schema/candidate_details.schema.json`
validam as duas estruturas estritas; `CandidateDataset` valida as relações entre elas.

- `summary.json` contém `source_dates`, `lisbon`, as 24 `parishes` e uma linha
  desconhecida no fim. Cada âmbito tem `official_count`, `listings_count`,
  `candidates_count`, `numbered_candidates_count` e `distinct_al_numbers_count`.
  As contagens RNAL e dos anúncios originais vêm independentemente das fontes.
  Os totais de anúncios e candidatos são aditivos; números distintos podem sobrepor-se.
- O resumo inclui as cinco contagens de sinais em `signals`,
  `repeated_number_distances` (seis intervalos, incluindo por resolver) e
  `outside_regions` (NUTS II, com `district: null` para regiões por resolver).
  Guarda apenas contagens; etiquetas, percentagens e geometria pertencem à apresentação.
- `candidates.json.gz` descodifica para `candidates` e `grouping_assessments`,
  incluindo todos os candidatos e declarações originais, mesmo os omitidos da tabela.
  Usa JSON UTF-8 compacto com newline final, Zlib nível 9, mtime zero, sem nome
  original nem comentário. Entradas idênticas reproduzem bytes no runtime suportado.

`CandidateDataset` expõe `summary_document`, `details_document`, `candidates` e
`grouping_assessments`; `summary` mantém os quatro valores Ruby de `Analysis.run`.
Os agregados derivados de candidatos são partilhados pelo builder e pela validação
através de `CandidateDataset.candidate_aggregates`.

Os IDs distintos referenciados têm de cobrir exatamente a população original.
Cada contribuição anúncio–número aparece uma única vez. Candidatos sem número
são individuais. `raw_licences` mapeia os IDs contribuintes para o texto original
ou `null`, sem normalizar o original. Esta publicação é uma exceção deliberada:
os restantes campos excluem anfitriões, descrições, nomes, endereços e coordenadas
exatas dos anúncios. Strings originais devem ser escapadas quando apresentadas.

### Declarações

Retemos anúncios cujo município normaliza para Lisboa e exigimos IDs numéricos
únicos. IDs inválidos/duplicados falham com os IDs indicados no erro. Campos obrigatórios
ausentes também falham.

Reconhecemos números simples, variantes AL, zeros iniciais, formatos antigos com
ano e whitespace Unicode/caracteres de formato nas extremidades. Em declarações
múltiplas extraímos todos os tokens AL explícitos, deduplicados por anúncio.
Fragmentos, números com separadores de milhares e outros regimes não são reparados.
O texto original integral fica em `raw_licences` e extrações parciais recebem um sinal;
não criam um candidato adicional sem número.

Sem número extraído, cada anúncio produz um candidato `absent`, `exempt` ou
`unrecognised`. Isenção exige uma declaração explícita de valor completo, como
`Exempt` ou `Isento`. Uma palavra incidental em prosa não basta. Isenções nunca
são números AL e não entram no agrupamento ou reutilização de números.

### Agrupamento

Apenas pares com o mesmo número AL não nulo são avaliados. RNAL não influencia
as decisões de agrupamento.

| Evidência | Pontos |
| --- | ---: |
| Distância até 50 m | 3 |
| Distância acima de 50 m até 100 m | 2 |
| Mesmo anfitrião não vazio | 1 |
| Títulos semelhantes | 2 |
| Descrições fortemente semelhantes | 3 |

Textos são descodificados de HTML, normalizados por Unicode/case e comparados
como conjuntos de tokens alfanuméricos, preservando números. Títulos exigem
Jaccard ≥0,5 e três termos comuns. Descrições exigem Jaccard ≥0,8 e pelo menos
30 termos distintos em cada texto. Evidência ausente vale zero.

Agrupar exige ≥7 pontos, coordenadas válidas até 100 m e categorias de quarto
compatíveis, sem contradição de unidade. Números de quartos conhecidos diferentes
em dois apartamentos inteiros impedem o agrupamento; diferenças entre anúncios
de quartos não estabelecem apartamentos distintos. Anfitriões diferentes não
impedem automaticamente o agrupamento.

Pares de 4–6 pontos ou bloqueados por informação em falta ficam em revisão,
separados. Distâncias acima de 100 m, categorias incompatíveis, contradições de
apartamento e pontuações até 3 ficam separados. A pontuação não é uma probabilidade.

O complete-link exige que **todos** os pares do grupo cumpram a regra. Escolhe-se
a união com maior pontuação mínima entre grupos e desempata-se por IDs ordenados.
Pares elegíveis impedidos por conflitos de grupo passam a revisão. IDs de candidatos
são hashes do número normalizado e dos IDs ordenados dos membros.

### Geografia e RNAL

O medóide é o membro com menor soma de distâncias Haversine aos outros membros
com coordenadas; empates usam o ID. Serve para freguesia por coordenadas e distância
ao RNAL. A freguesia atribuída exige unanimidade dos membros numa freguesia Airbnb
reconhecida. A geografia Airbnb não está verificada; coordenadas não substituem a
atribuição. Freguesias Airbnb, por coordenadas e oficiais ficam separadas.

`data/freguesia_boundaries.json` conserva apenas nomes e polígonos CML completos,
com atribuição e hash SHA-256 do original. O original fornecido está em
`data_sources/lisboa-freguesias.geojson`, também versionado. É a única exceção
à exclusão de fontes locais pela auditoria; CSVs Airbnb/RNAL continuam excluídos. CI usa a derivação sem downloads.
O mapa visual simplificado em `site/_data/freguesia_map.json` continua separado.

Por número nacional RNAL, valores não vazios normalizados concordantes são
conservados; conflitos ficam `null`. Coordenadas são resolvidas
como pares. Conflitos de município deixam freguesia e localização por resolver.
Não escolhemos a primeira linha nem a localização mais próxima. `found` significa
que o número existe nacionalmente, mesmo com campos por resolver. `NUTSII` alimenta
`official_match.district`. Resumos RNAL são calculados independentemente sobre as
linhas que declaram Lisboa, antes da resolução nacional.

## Métricas de registo

Preservamos as unidades da apresentação:

- O diagrama conta todos os candidatos no Airbnb, os candidatos com número na
  interseção e os sem número na área exclusiva. RNAL conta números distintos.
  Números repetidos contam uma vez por candidato. Quando excedem RNAL, mostramos
  contagens sem geometria proporcional impossível. Medidas desconhecidas mostram `???`.
- O sinal sem número identificável conta IDs distintos `absent`/`unrecognised`,
  excluindo isenções declaradas.
- O sinal de reutilização conta IDs distintos em números associados a vários
  candidatos. O gráfico conta cada número uma vez, usando a maior distância ao
  RNAL entre os candidatos. Correspondências ou distâncias em falta ficam por resolver.
  Intervalos: até 500 m, 500 m–1 km, 1–2 km, 2–5 km e mais de 5 km.
- O sinal fora de Lisboa conta IDs distintos com município oficial conhecido
  diferente de Lisboa. Regiões NUTS II em falta ou contraditórias ficam por resolver.

## Arquitetura e substituição segura

`Analysis.run` prepara fontes uma vez (`DataSource`), constrói um `CandidateDataset`
validado com `DatasetBuilder` e publica-o com `ResultPublisher`. O dataset é o mesmo
objeto de dados usado para snapshots gerados e carregados, incluindo o resumo.
`Declaration`, `Grouping` e `Boundaries` são colaboradores focados; Zeitwerk mantém
nomes/caminhos coerentes.

O builder compara contribuições e resumos diretamente com as fontes preparadas.
A publicação prepara os dois ficheiros numa pasta irmã temporária, fecha e sincroniza
os ficheiros, valida e relê o par por `CandidateDataset` antes de obter o lock exclusivo.
Verifica novamente os hashes das fontes e substitui a pasta datada com backup e rollback
em caso de exceção ou interrupção. O lock está na pasta mãe estável; leitores e cópias
para downloads usam locks partilhados. As cópias verificam os hashes dos ficheiros usados
na renderização e falham se estes mudarem durante o build.
Os manifestos das
fontes e a atribuição/hash dos limites ficam junto dos respetivos inputs.
Não há diagnósticos persistidos nem histórico analítico separado.

### Impacto da substituição

No mesmo par `2026-06-23__2026-09-26`, os bytes SHA-256 permanecem os mesmos e a
população original continua em **17 064 anúncios**; o resumo RNAL continua em
**11 869 números distintos**. A estimativa antiga de 14 600 estabelecimentos
usava componentes espaciais até 500 m e categorias gerais. O novo método usa
extração múltipla, pontuação e complete-link até 100 m, produzindo **16 210 candidatos**
na primeira execução. Estas duas estimativas têm métodos e unidades diferentes;
não medem uma variação temporal. As regras estão documentadas acima.
Os outputs antigos foram removidos da árvore atual por alterações Git normais;
o histórico Git permanece intacto.

## Verificar

```bash
bundle exec rake test
npm run site:lint
DESTINATION=tmp/candidate-site bundle exec rake site:build site:check
ruby scripts/audit_publication.rb
ruby scripts/audit_publication.rb --artifact tmp/candidate-site
```

Testes incluem parsing, isenções repetidas, limiares, cadeias, desempates, medóide,
polígonos completos, conflitos RNAL, contabilidade, proveniência e preservação do snapshot em falhas.
`test/fixtures/pipeline/sources/` contém um caso sintético com 11 anúncios retidos,
12 contribuições e 11 candidatos, com outputs revistos em `expected/`.
A fixture de apresentação é inventada e conserva 13 anúncios, 12 candidatos e
17 números RNAL; não é output dessa fonte sintética.

HTML/Liquid: `npm run site:format` e `npm run site:lint`. PDF usa o
`wkhtmltopdf-binary` incluído no bundle, sem fallback. O utilizador trata de
screenshots nesta etapa. Não descarregar fontes, capturar screenshots ou publicar
para validar mudanças locais.

## CI

O workflow mensal testa, restaura fontes, atualiza explicitamente quando necessário,
arquiva só o par selecionado e manifestos, executa análise, audita e faz staging
apenas de `summary.json` e `candidates.json.gz` da pasta datada gerada. Constrói o site e inspeciona `_site/report.pdf`.
O workflow de site constrói sem análise. Ambos usam a auditoria do contrato de
candidatos. CSVs brutos e manifestos locais ficam fora do Git.
`ruby scripts/audit_publication.rb --history` audita segurança do histórico sem
adicionar leitores legados. Reescrever histórico exige backup recuperável e aprovação
coordenada; esta substituição não o reescreve.

Trabalho futuro está em [TODO.md](TODO.md).
