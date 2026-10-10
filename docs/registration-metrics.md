# Métricas de registo AL

Análise 3.1.0 · metodologia 2.0.0 · schema público 4.0.0 · métricas de conjuntos 1.0.0.

Run verificado: `2026-06-23__2026-09-26`. Recalculado com os mesmos bytes da fonte datada. Existe uma pasta por par de datas; as versões da análise e metodologia estão no metadata. A reanálise substitui a pasta e as suas linhas históricas após validação. Outros pares de datas permanecem iguais; o Git conserva resultados anteriormente commitados. Comparações entre metodologias diferentes continuam incompatíveis. A análise 3.1.0 simplifica a identidade e substituição dos outputs públicos, sem alterar os cálculos da metodologia 2.0.0.

## Fontes e datas

- Airbnb, arquivo de 2026-06-23: SHA-256 `e7a8d69b67dcef47c7659acd6e268570d1ed9db57ef6ac16bea6259003bbbea8`.
- RNAL, descarregado em 2026-09-26: SHA-256 `1d15ad8e799ea426f2b5a246db4f6b80544d7dbfc5b2d1d67bc5de06fb023fc8`.

As datas de `last_scraped` pertencem aos anúncios. O campo legado `official_register_date` é a maior `DataRegisto` entre registos associados aos anúncios, não a data de observação do RNAL. O site apresenta a data de download. Nenhuma destas fontes foi apresentada como um novo download de outubro.

`metadata.json` regista o commit base e `git_worktree_dirty: true`, pois este trabalho não foi committed. A reprodução exata do código depende de guardar estas alterações; o commit base sozinho não as contém.

## Unidades e geografias

`registration_metrics.json` contém 26 linhas: Lisboa, 24 freguesias e um agregado de geografia não identificada. Cada linha tem:

| Campos | Unidade e definição |
| --- | --- |
| `rnal`, `airbnb` | Números AL normalizados distintos em cada conjunto local |
| `intersection`, `rnal_only`, `airbnb_only` | Interseção e diferenças dos conjuntos locais |
| `another_lisbon_parish`, `another_municipality`, `no_national_match`, `unresolved_official_geography` | Partição exaustiva de `airbnb_only`, em números distintos |
| `announcements` | Anúncios observados com município Lisboa |
| `empty_licence`, `unrecognised_licence`, `identifiable_number` | Partição exaustiva dos anúncios: vazio, preenchido não reconhecido, número identificável |
| `confirmed_rnal_match` | Anúncios cujo número identificável existe no RNAL nacional datado; subconjunto de `identifiable_number` |
| `official_entries` | Linhas oficiais com Concelho Lisboa, sem deduplicar entradas |

O RNAL usa `Concelho` e `Freguesia` oficiais; o Airbnb usa o município e a freguesia observados. Há normalização de espaços, maiúsculas e acentos, com aliases explícitos para as oito grafias Airbnb que perderam letras acentuadas. Freguesias desconhecidas não são atribuídas a nenhuma das 24; entram no total municipal e num agregado próprio. Esse agregado não afirma correspondências locais: a sua interseção é zero.

O total municipal é calculado diretamente. Um número Airbnb pode existir em várias freguesias. RNAL-only significa ausência no Airbnb da mesma geografia; Airbnb-only não significa ausência no registo nacional.

Entre números Airbnb-only, ausência de registo nacional é distinguida de geografia por resolver. Concelhos vazios/desconhecidos, conflitos entre concelhos, e freguesias oficiais de Lisboa desconhecidas/conflituantes (na análise distrital) ficam por resolver. Várias entradas oficiais iguais contam uma vez no conjunto. Nomes não vazios de outros municípios, exceto marcadores explícitos de desconhecido, são aceites como declarados pela fonte, sem validação externa de uma lista nacional de municípios.

As métricas são contagens, sem percentagens implícitas. Percentagens dos sinais usam anúncios; distribuições de distâncias usam números; distribuições regionais usam os anúncios com registo oficialmente noutro concelho. As áreas dos dois círculos e a interseção são proporcionais aos conjuntos em cada diagrama. A bolha separada tem área proporcional à fração de anúncios sem número identificável, numa escala independente. Tamanhos de diagramas diferentes não servem de escala comum.

## Resultados e verificações

| Lisboa | Contagem |
| --- | ---: |
| RNAL distinto / entradas oficiais | 11 869 / 11 869 |
| Airbnb distinto | 8 888 |
| Interseção | 7 287 |
| Só RNAL local | 4 582 |
| Só Airbnb local | 1 601 |
| Destes: outro município / sem RNAL nacional | 363 / 1 238 |
| Anúncios | 17 064 |
| Campo vazio / preenchido não reconhecido | 633 / 3 704 |
| Número identificável / correspondência nacional | 12 727 / 10 643 |
| Estabelecimentos estimados | 14 600 |

A fonte RNAL tem 111 776 entradas nacionais, sem números não reconhecidos, duplicados de número ou concelhos por resolver. As 11 869 entradas de Lisboa têm freguesia reconhecida. Não há geografia observada desconhecida nos anúncios de Lisboa deste arquivo. Os caminhos de casos não resolvidos e duplicados são cobertos por fixtures.

O prefixo `Registration Number:` ocorre num anúncio deste arquivo. A normalização 2.0.0 aceita apenas um número único seguido de `/AL`, com prefixo ancorado. Mantém os formatos anteriores (algarismos, AL antes/depois, zeros iniciais, ano legado 2010–2029) e exclui `/UT/YYYY`, texto livre e múltiplos números. Os valores originais são mantidos internamente em `licensa_raw` e nunca exportados nos agregados públicos.

## Classificação e estimativa

A prioridade consta das definições versionadas: campo não identificável; município oficial conhecido fora de Lisboa; coordenadas observadas por resolver; vários agrupamentos espaciais; ausência no RNAL; concelho oficial por resolver; número único com registo Lisboa; provável estabelecimento múltiplo; repetição na mesma localização.

O agrupamento de 500 m calcula componentes conexas; extremos ligados por uma cadeia podem distar mais de 500 m. Coordenadas ausentes não são convertidas para zero. Identificadores de anfitrião não agrupam anúncios. A indicação de unidades/quartos usa modalidade oficial ou pelo menos metade dos nomes/tipos com termos como quarto, hotel ou apartamento; é uma heurística, sem confirmação de um estabelecimento.

A estimativa colapsa apenas os dois grupos de menor risco na mesma localização com correspondência oficial Lisboa. Mantém separados anúncios sem correspondência, geografia por resolver, registo externo e reutilização em várias localizações. É calculada independentemente para cada freguesia, pelo que também não se deve somar para obter Lisboa. Os grupos de licença excluem os dois agregados sem número; `spatial_locations` conta agrupamentos de 500 m, não pares de coordenadas diferentes.

Estas correções alteram a estimativa anterior e o significado das categorias. A versão da metodologia foi aumentada para 2.0.0; não há comparação numérica com a anterior. Um número encontrado não confirma validade, atividade ou localização real. Os indicadores não são conclusões legais.

## Reprodução e publicação

```sh
bundle exec ruby scripts/reanalyse_public_run.rb 2026-06-23__2026-09-26
```

O script verifica os hashes antes de calcular e substitui os outputs do mesmo par de datas após validar o candidato. A instalação restaura os ficheiros anteriores se falhar. `--reuse-existing` exige hashes, versões de análise/metodologia/schema e ficheiros atuais; versões anteriores são recalculadas, sem criar uma pasta adicional.

O snapshot `2026-06-23__2026-10-01` e as suas linhas históricas foram importados de `origin/main` sem alterações. Usa metodologia 1.1.0 e ainda não contém métricas de conjuntos. O CSV RNAL original de outubro não está disponível localmente (SHA-256 esperado `b35c757828e30789bbbd11b4e19c785ef0c49ea5bcb2865f548abf99c030992d`). Um download atual não reproduz essa fonte. O site usa os números verificados de setembro e indica a existência do snapshot mais recente ainda sem estas métricas.

Os testes cobrem formatos, conjuntos locais, duplicados, geografia por resolver, conservação das contagens, prioridades, transitividade, anfitriões e geometria vazia/disjunta/idêntica/contida. A auditoria inclui ficheiros públicos novos ainda não tracked e o artefacto gerado. Dados publicados contêm apenas agregados, definições e proveniência; relatórios exemplificativos mantêm a indicação de exemplos sintéticos.

Validação final: 37 testes, 221 asserções, sem falhas; syntax checks de Ruby; recomputação independente dos conjuntos nas 26 geografias e reconciliação dos CSV; auditoria dos novos snapshots e de `_site`; build de 31 páginas HTML com 24 freguesias. Homepage, índice, Arroios, Santa Clara e metodologia foram capturados e inspecionados a 1440, 768 e 390 px, sem overflow horizontal. A simplificação das pastas não alterou as contagens medidas. Os snapshots de 18/19 de setembro e os ficheiros de outubro permaneceram iguais byte a byte; só as linhas históricas do par de setembro recalculado foram substituídas. `lisboa-freguesias.geojson` permaneceu intocado.
