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
  desconhecida no fim. Usa JSON indentado para facilitar os diffs Git.
  Cada âmbito tem `official_count`, `listings_count`,
  `candidates_count`, `numbered_candidates_count`, `distinct_al_numbers_count` e
  `matched_al_numbers_count` (números distintos comuns às duas fontes no mesmo âmbito).
  `exempt_candidates_count`, `empty_licence_candidates_count` e
  `unrecognised_licence_candidates_count` e `mixed_licence_candidates_count` completam a divisão exclusiva dos candidatos
  juntamente com `numbered_candidates_count`.
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
Cada contribuição declarada anúncio–número aparece uma única vez. Candidatos sem número
podem ter vários membros quando a evidência de unidade o permite. `raw_licences` mapeia os IDs contribuintes para o texto original
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

Sem número extraído, a declaração individual é `absent`, `exempt` ou
`unrecognised`. Isenção exige uma declaração explícita de valor completo, como
`Exempt` ou `Isento`. Uma palavra incidental em prosa não basta. Isenções nunca
são números AL nem evidência de identidade.

### Agrupamento

Um único conjunto de anúncios alimenta o matcher. Descobrimos pares pela união
de vizinhos até 500 m (grelha espacial), números AL não-placeholder partilhados e
referências explícitas de apartamento/unidade partilhadas. Cada par é avaliado uma
vez, independentemente do anfitrião ou declaração. 500 m é raio de procura, não
prova de identidade; números e referências permitem avaliar pares mais distantes.
RNAL não acrescenta pontos nem autoriza fusões; pode resolver a separação de
apartamentos com registos distintos e localmente consistentes, como descrito abaixo.

| Evidência | Pontos |
| --- | ---: |
| Coordenadas até 500 m | 1 |
| Mesmo anfitrião não vazio | 1 |
| Títulos semelhantes | 2 |
| Descrições fortemente semelhantes | 3 |
| Mesma referência explícita de apartamento/unidade | 3 |
| Mesmo número AL declarado não-placeholder | 2 |
| Compatibilidade de quartos/apartamento com o mesmo anfitrião, AL e descrição forte | 1 |

Textos são descodificados de HTML, normalizados por Unicode/case e comparados
como conjuntos de tokens alfanuméricos, preservando números. Títulos exigem
Jaccard ≥0,5 e três termos comuns. Descrições exigem Jaccard ≥0,8 e pelo menos
30 termos distintos em cada texto. Evidência ausente vale zero. Extraímos
`apartment`, `flat`, `apartamento`, `apt` e `unidade` seguidos de identificador
numérico, alfanumérico ou letra única; múltiplas referências distintas são ambíguas.
Referências de quarto/cama (`room`, `quarto`, `bed`, `cama`) ficam separadas.
Sufixos plurais, possessivos, abreviaturas de prosa, artigos, contagens de quartos,
intervalos de capacidade e tipologias T1/T2/T3 não identificam unidades.

Agrupar exige ≥8 pontos, coordenadas válidas até 500 m, ausência de contradição e:
referência de apartamento partilhada mais semelhança de texto, ou número AL
partilhado mais títulos e descrições semelhantes nos limiares acima, ou a via
de quartos do mesmo anfitrião abaixo. Outras relações entre categorias diferentes
continuam a exigir referência explícita comum.
Referências de apartamento diferentes e atributos conhecidos contraditórios entre
apartamentos inteiros (tipo de propriedade, quartos, camas, casas de banho e
capacidade) impedem fusão automática. Diferenças entre quartos não estabelecem
apartamentos distintos. Anfitriões diferentes não impedem automaticamente a fusão.
Partilhar edifício, piso, anfitrião ou texto genérico não basta.

A via `same_host_room_group` exige o mesmo anfitrião não vazio, um único AL comum
integralmente declarado, coordenadas até 500 m e descrições com pelo menos 30
termos distintos por texto e Jaccard ≥0,8. Pelo menos um anúncio tem de ser
`Private room`; o outro pode ser outro quarto privado ou um apartamento inteiro
com tipo de propriedade reconhecido como apartamento. Essa compatibilidade vale
1 ponto, somado aos 7 de proximidade, anfitrião, AL e descrição forte, mantendo o
mínimo de 8. Não exige títulos semelhantes nem frases ou medidas específicas.
Referências explícitas de apartamentos diferentes, números AL contraditórios ou
múltiplos impedem fusão. Quartos partilhados, hotéis e categorias desconhecidas
não entram nesta via. Dois anúncios inteiros continuam sujeitos às regras de
duplicados e aos conflitos de atributos; diferenças de quartos/capacidade entre
um quarto e o apartamento inteiro são esperadas e não contradizem a fusão.

Pares de quarto/apartamento ficam `apartment_and_rooms`; quartos privados ficam
`separate_rooms`, salvo referência explícita ao mesmo quarto/cama, que permite
`duplicate_adverts`. Todos os pares têm de qualificar, incluindo os pares de
quartos entre si: quatro quartos e um apartamento exigem dez pares elegíveis.
A contagem de quartos é apenas apoio de revisão, não uma condição que exige
observar todos os quartos do apartamento. Texto-modelo pode dar falsos positivos;
partilhar anfitrião/AL não estabelece identidade sem a restante evidência.

Pares plausíveis sem cumprir todos os requisitos ficam separados, em revisão.
Conflitos de números AL e anúncios com múltiplos números nunca autorizam fusão.
Um par plausível até 500 m pode ficar resolvido como `separate_apartments`, com
`outcome: separate` e `distinct_registered_apartments`, quando ambos são anúncios
Airbnb de apartamentos inteiros e cada um tem uma declaração integral com um
único número AL diferente. Os dois registos nacionais têm de resolver modalidade
Apartamento, município Lisboa e coordenadas até 500 m do respetivo anúncio.
Referências explícitas de apartamento partilhadas, extrações parciais, múltiplos
números, quartos, propriedades desconhecidas e campos RNAL por resolver ou
inconsistentes mantêm o caso para revisão. A evidência RNAL vale zero pontos e
apenas resolve uma separação já impedida pelo conflito de números; não altera as
fusões. Coordenadas próximas ou iguais não provam que seja o mesmo edifício.

Dois anúncios de alojamentos inteiros com o mesmo número AL também ficam
resolvidos como `separate_apartments` / `separate` quando diferem simultaneamente
no número conhecido de quartos, camas e capacidade (`distinct_apartment_attributes`).
Também podem resolver-se assim quando o número de quartos coincide, mas camas e
capacidade diferem na mesma direção (mais camas e mais hóspedes) e os textos são
claramente distintos (`different_apartment_text`):
Jaccard ≤0,25 tanto nos títulos como nas descrições, com pelo menos 3 termos
distintos por título e 30 por descrição. Este limiar inicial exige dissemelhança
positiva; falhar o teste de semelhança forte não basta, e texto em falta não é
evidência de separação. O motivo vale zero pontos e não altera fusões.
Contagens de camas e capacidade que variam em sentidos opostos não encerram
revisão por esta alternativa: podem refletir dados inconsistentes ou configurações
de ocupação diferentes. O número AL continua assinalado como partilhado entre
candidatos, mesmo depois de uma relação ficar resolvida como separação.
Uma referência explícita de apartamento partilhada ou declarações com números
conflituantes/múltiplos impedem esta regra. Valores ausentes ou malformados são
desconhecidos; uma diferença isolada continua para revisão. Esta evidência não
atribui pontos, não altera fusões e não determina qual anúncio corresponde ao RNAL.

Pares próximos sem identidade plausível são avaliados e descartados; os restantes
assessments publicados são únicos por par de IDs, com `outcome`, `score`,
`relationship` (`duplicate_adverts`, `separate_rooms`, `apartment_and_rooms`,
`undetermined`, `separate_apartments`) e
códigos de evidência em `reasons`. A pontuação não é uma probabilidade.

Cada assessment publica ainda `distance_m` (metros, arredondados à unidade,
ou null), `title_comparison` e `description_comparison` (Jaccard com quatro
casas decimais, contagens de termos distintos e termos comuns), `room_types`,
`property_types` normalizados e `attributes` (quartos, camas, casas de banho e
capacidade). Os pares de valores seguem exatamente a ordem de `listing_ids`.
Textos ausentes têm semelhança null; atributos ausentes/malformados também são
null. As decisões usam os valores não arredondados. Assim, uma distância publicada
de 500 m pode ficar de qualquer lado do limiar; o motivo de distância mantém a
comparação original. As coordenadas Airbnb continuam aproximadas.

`evidence` detalha a categoria (`supporting`, `contradicting`, `unknown`) e os
`points` de cada código em `reasons`; a soma reproduz `score`. Categorias e
referências de quarto podem apoiar a interpretação da relação sem pontuar
identidade. Contradições continuam com zero pontos e os bloqueios existentes;
não se introduziram penalizações nem novos pesos por distância nesta revisão.
`decision_reason` separa a decisão da evidência: `merge_threshold`,
`insufficient_merge_evidence`, `insufficient_identity`, separação fundamentada ou
`complete_link_conflict`. O último identifica um par elegível deixado de fora
pela coerência do grupo. `insufficient_merge_evidence` substitui o nome ambíguo
`review_score`: não utiliza avaliações Airbnb e não atribui pontos.
Não publicamos textos, anfitriões ou coordenadas exatas nestes detalhes.

`undetermined` é o valor por defeito: uma fusão de alojamento não prova que os
anúncios sejam duplicados. `duplicate_adverts` exige um par elegível para fusão,
com a mesma categoria conhecida e, para quartos/camas, a mesma referência
explícita de quarto/cama (`same_room_reference`). Dois anúncios de apartamentos
inteiros podem ser classificados assim pela evidência de identidade existente.
Pares plausíveis com evidência insuficiente ou contraditória ficam `undetermined`,
salvo quando as categorias/referências identificam uma relação de quartos ou
uma regra de separação identifica apartamentos distintos.
A classificação não altera pontuações nem grupos. A regra de apartamentos
registados distintos pode resolver `review` como `separate`.


O complete-link exige que **todos** os pares do grupo cumpram a regra. Escolhe-se
a união com maior pontuação mínima entre grupos e desempata-se por IDs ordenados.
Pares elegíveis impedidos por conflitos de grupo passam a revisão. IDs de candidatos
são hashes do número associado e dos IDs ordenados dos membros.

Grupos podem combinar declarações numeradas, ausentes, de isenção e não reconhecidas.
`al_number` associa o candidato ao único número utilizável declarado pelo conjunto;
não significa que todos os membros o tenham declarado. As declarações individuais
permanecem integralmente em `raw_licences`. Sem número, conservamos a categoria
comum ou `mixed` quando divergem. Anúncios com vários números mantêm contribuições
separadas por número e apenas relações para revisão. Sinais de ausência/declaração
não reconhecida contam IDs a partir das declarações individuais, mesmo em grupos
numerados. Associações inferidas não acrescentam declarações às fontes.

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

As métricas usam as seguintes unidades:

- O diagrama em forma de Venn dimensiona os círculos pelo total de registos RNAL e
  pelo total de candidatos Airbnb. A sobreposição conta cada número comum uma vez,
  mesmo quando vários candidatos o declaram (`matched_al_numbers_count`). As áreas
  exclusivas são RNAL menos números comuns e candidatos menos números comuns.
  «Restantes candidatos» pode incluir reutilizações de números existentes no RNAL.
  É uma convenção de contagem; não escolhe qual candidato representa corretamente um registo.
- A barra horizontal de 100% reparte os candidatos sem duplicações: uma ocorrência por
  número comum, ocorrências adicionais de números reutilizados, uma ocorrência por número
  fora do RNAL deste âmbito, declaração não reconhecida, declarações mistas sem número, isenção declarada por verificar
  e ausência de declaração. Reutilização é candidatos com número menos números distintos.
  Os números reconhecidos fora do RNAL do âmbito aparecem separados dos valores não
  reconhecidos; podem existir noutra freguesia/município ou não ser encontrados nacionalmente.
  Não se classificam isenções como corretas/incorretas sem critérios e evidência.
- RNAL usa as linhas originais que declaram Lisboa e, nas freguesias, a mesma freguesia
  oficial (incluindo desconhecida), antes da resolução nacional. Conflitos não apagam
  essas pertenças. Números e reutilizações por freguesia podem sobrepor-se e não são
  necessariamente aditivos. A construção verifica a contagem comum face às fontes;
  a leitura verifica os limites dos conjuntos. Encontrar o número não confirma a
  identidade nem a legalidade do alojamento. As categorias da barra usam candidatos,
  não os sinais de anúncios distintos.
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

No mesmo par `2026-06-23__2026-09-26`, a reanálise local conserva os hashes das
fontes, **17 064 anúncios**, **11 869 números RNAL**, **8 923 números AL declarados**
e **7 320 números comuns** às fontes em Lisboa. A cobertura foi verificada
independentemente por leitura dos CSVs: todos os IDs, cada declaração original,
cada contribuição anúncio–número e os totais originais por freguesia concordam.

| Categoria de candidatos | Método anterior | Matcher único |
| --- | ---: | ---: |
| Com número associado | 11853 | 11845 |
| Isenção declarada | 3585 | 3585 |
| Sem declaração | 633 | 633 |
| Declaração não reconhecida | 139 | 139 |
| Mistas sem número | 0 | 0 |
| Total | 16210 | 16202 |

Há **452 candidatos com vários anúncios**, com 893 contribuições a menos do que
se cada contribuição individual permanecesse separada.
Os pares internos aceites distribuem-se por `duplicate_adverts`: 592; `separate_rooms`: 323; `apartment_and_rooms`: 0; `undetermined`: 1163.
Estas são contagens de pares, não de candidatos; todos os pares de cada grupo
cumprem os critérios. O maior grupo tem 24 anúncios.

Neste par, 0 candidatos associam membros sem número utilizável a um número
declarado por outro membro. Os casos de associação inferida, grupos inteiramente
sem número e categorias mistas são exercitados pelas regressões sintéticas.
Os sinais individuais de ausência (633) e declaração
não reconhecida (139) mantêm-se independentes da associação do candidato.

A regra de apartamentos registados distintos resolve **6 358 pares** antes em
revisão, sem alterar candidatos, pontuações ou fusões. O número de candidatos
com o sinal `grouping_review` passa de **8 661 para 6 934**. O par revisto
`1000837114643475255` / `1003445988121476426`, com números 84776 e 84783,
fica `separate` / `separate_apartments`, com 7 pontos e motivo
`distinct_registered_apartments`. Ambos os RNAL resolvem Apartamento em Lisboa
com localização até 500 m do respetivo anúncio. Não se infere identidade de edifício.

A revisão local incluiu estes pares de IDs:

| Par | Avaliação |
| --- | --- |
| 1000672424786379990 / 1019708606943533804 | Aceite: `undetermined`, 9 pontos |
| 1035272767626393810 / 1035274669525746246 | Aceite: `separate_rooms`, 9 pontos |
| 1055110451722367068 / 1056413133220721741 | Separados: apartamentos com números distintos e registos RNAL localmente consistentes |
| 1001799626325440617 / 1004495237965399867 | Revisão: atributos de apartamento contraditórios |
| 1000672424786379990 / 48377666 | Revisão: números AL diferentes |
| 1019708606943533804 / 48900551 | Revisão: conflito complete-link |

Foram também revistos exemplos de apartamentos autónomos com texto
repetido: sufixos plurais, abreviaturas, quebras entre campos/parágrafos, artigos,
contagens e tipologias não fornecem referências de unidade. As regras são
indicadores de investigação; a diferença no total resulta do método, não de
uma variação temporal nem de um objetivo de redução.

### Revisão do snapshot de setembro

O par local `2026-09-19__2026-09-26` contém **17 153 anúncios**, **15 920 candidatos**,
**8 784 números AL declarados**, **11 869 números RNAL** e **7 247 números comuns**
em Lisboa. Todos os IDs e declarações originais foram novamente confrontados com
os CSVs, independentemente da validação do builder. A fixture de apresentação
conserva os seus totais.

A substituição das frases específicas pela via anfitrião/AL/descrição reduz os
candidatos de 16 288 para 15 920. Passam a aceites 1 053 pares `separate_rooms`,
84 `apartment_and_rooms` e 4 `duplicate_adverts`; 15 pares anteriormente aceites
ficam em revisão, dois pela remoção da via de frases e 13 por conflitos complete-link
após a alteração da prioridade das uniões. Existem 24 candidatos que combinam
anúncios de quartos e apartamento inteiro. São contagens de pares/candidatos,
não confirmação de identidade. Texto-modelo continua a requerer revisão.

No portefólio revisto, os anúncios `23051174`, `23072681`, `23072930` e `23073155`
(quartos 201–204, com 35505/AL) formam um candidato. Os anúncios de apartamentos
2E (`23482919`) e 3E (`15174813`) permanecem separados. O par
`1001265559722983156` / `1001268286809894172` volta a revisão: a semelhança de
74% das descrições fica abaixo dos 80% exigidos. Não se baixou o limiar para
preservar um exemplo previamente aceite.

Foi também revisto um grupo com o anúncio inteiro `1031336398040002282` e quartos
como `1075984734133615455` e `1460291600840328268`, todos com 87507/AL:
as descrições distinguem apartamento inteiro e quarto privado partilhando o
restante texto. O par `1386202580695011904` / `1386204287560026943`, de anúncios
inteiros, fica em revisão por conflito complete-link. Esta via não autoriza
fundir dois anúncios inteiros sem a evidência exigida pelas regras anteriores.

Uma revisão posterior das separações resolve **76 pares** com camas e capacidade
diferentes na mesma direção e textos claramente distintos, sem exigir diferença
no número de quartos. O par `10020044` / `9634390` fica `separate` /
`separate_apartments`, com `distinct_apartment_attributes` e 4 pontos. Ambos mantêm
o sinal `shared_number` para 4037/AL; relações com outros anúncios desse número
continuam por resolver. Candidatos com revisão passam de 6 031 a 5 997, sem mudar
grupos, pontuações, totais ou cobertura. O par `1036096431487851829` / `37649719`
permanece em revisão: os números de camas e hóspedes variam em sentidos opostos.

### Primeira classificação de portefólios de anfitriões

Uma leitura local do snapshot de setembro distingue **5 827 anfitriões**, cobrindo
os mesmos 17 153 anúncios, sem IDs de anfitrião ausentes. Estas classes descrevem
apenas os anúncios observados, não conformidade ou confiança:

| Categorias observadas no portefólio | Anfitriões | Anúncios |
| --- | ---: | ---: |
| Apenas alojamentos inteiros (`Entire home/apt`) | 4 805 | 11 295 |
| Apenas quartos privados (`Private room`) | 735 | 2 080 |
| Mistura dessas duas categorias | 236 | 3 319 |
| Outras combinações ou categorias desconhecidas | 51 | 459 |

Entre grupos de um mesmo anfitrião com um único AL integralmente declarado por
anúncio, 481 grupos de 321 anfitriões têm pelo menos dois quartos privados.
Destes, 30 grupos de 26 anfitriões também têm vários anúncios de alojamentos
inteiros; 19 grupos de 12 anfitriões têm quartos separados por mais de 500 m.
São indicadores sobrepostos para revisão, não decisões de fusão/separação.

O portefólio revisto de 51 anúncios tem 40 quartos privados e 11 alojamentos
inteiros. Sob 35505/AL aparecem os anúncios `15174813` e `23482919`, relativos a
unidades designadas 3E e 2E, além de quartos e lofts; sob 115214/AL aparecem
`1711102860867040462` e `49121344`, descrevendo apartamentos com seis e cinco
suites. Áreas e contagens semelhantes também se repetem entre unidades anunciadas.
Assim, não se introduziu uma exceção que funda automaticamente quartos apenas
por partilharem anfitrião e AL. Os perfis podem orientar a revisão, mas ainda é
necessária evidência da unidade dentro de cada portefólio. A classificação descritiva não fornece exceções de confiança nem altera por si
só os grupos; a via de fusão anfitrião/AL/descrição acima é uma regra por par.

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
