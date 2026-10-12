# Pipeline de análise

A análise 3.1.1 usa o namespace `AlojamentoLocal`, carregado por
`lib/alojamento_local.rb`, e separa aquisição, preparação, classificação, cálculo
e publicação.
A metodologia continua em 2.0.0, o schema público em 4.0.0 e as métricas de
registo em 1.0.0. Esta refatorização não altera definições ou resultados.

1. `Data.prepare!` obtém os caminhos das fontes datadas. O CLI verifica a
   possibilidade de reutilização antes de executar a análise. O wrapper de
   reanálise verifica os hashes das fontes anteriores e usa o mesmo pipeline.
2. `PreparedSources::Pair` lê cada CSV uma vez, sem cache entre execuções.
   As entradas oficiais conservam os campos originais, número e geografia
   normalizados. Os índices nacionais e de freguesia contêm todas as entradas,
   incluindo duplicados, números não reconhecidos e conflitos.
3. `Analysis.classify` usa as linhas Airbnb preparadas e o lookup oficial
   derivado. Esse lookup escolhe a primeira entrada por número e deixa concelho
   e coordenadas por resolver quando existem locais oficiais diferentes.
   A derivação não modifica as entradas usadas pelas métricas. `licensa_raw`
   permanece nos dados internos; anfitriões não determinam agrupamentos.
4. `RegistrationMetrics.calculate` calcula conjuntos, interseções e diferenças
   a partir das mesmas entradas e índices completos. `AnnouncementCounts`
   partilha as contagens de anúncios. Contagens de números distintos, entradas
   oficiais e estimativas de estabelecimentos continuam a ser unidades separadas.
   A cidade e as freguesias são calculadas independentemente.
5. `Analysis.run` prepara grupos e agregados uma vez. `write_outputs` recebe os
   resultados e reutiliza os mesmos agregados públicos nos CSV e no relatório.
   O resumo conta entradas oficiais Lisboa, incluindo duplicados. A verificação
   de hashes, validação, staging, substituição e rollback permanecem no pipeline;
   execuções locais conservam a sua imutabilidade.
6. `SiteData` seleciona snapshots públicos e prepara os dados Liquid sem ler
   fontes privadas. Cada instância carrega os JSON uma vez e cria uma cópia das
   métricas para acrescentar geometria. `scripts/build_site.rb` invoca Jekyll,
   copia os outputs públicos e audita o artefacto. `Geography` centraliza a
   normalização, os nomes de apresentação e os aliases das rotas existentes.

Os métodos `licensed_als(path)`, `Analysis.analyse(airbnb_path, official_path)`
e `RegistrationMetrics.calculate(listings, official_path)` continuam disponíveis
como adapters. O pipeline principal passa fontes preparadas diretamente.
Não existe cache por nome de ficheiro: uma nova preparação lê os bytes atuais.

## Verificação

Os testes de preparação correm também através de `test/versioned_analysis_test.rb`.
Cobrem preservação de entradas e valores originais, duplicados idênticos,
conflitos de concelho/freguesia/coordenadas, geografia desconhecida, números
não reconhecidos, contagens de reutilização, mudança dos bytes no mesmo caminho,
uma leitura e normalização por fonte, aliases e leitura dos JSON do site.
Os testes existentes continuam a verificar publicação, rollback, métricas e
regras espaciais.

`test/pipeline_regression_test.rb` acrescenta uma comparação permanente com
fontes inteiramente sintéticas e 19 outputs esperados guardados em
`test/fixtures/pipeline/expected/`. Corre automaticamente com `bundle exec rake test` nos dois workflows CI. Compara os outputs públicos e locais,
históricos e dados do site, retendo versões, hashes, definições e todas as linhas.
Só substitui timestamps de geração e proveniência Git nos campos explicitamente
identificados. Contagens independentes verificam os conjuntos e a estimativa;
um teste adicional audita o artefacto público sintético. Ver
[fixture e atualização dos resultados esperados](../test/fixtures/pipeline/README.md).

A comparação completa usou os mesmos bytes de
`listings-2026-06-23.csv` e
`Estabelecimentos_de_Alojamento_Local-2026-09-26.csv`, com os hashes documentados
em [registration-metrics.md](registration-metrics.md). Foram comparados 19
ficheiros em diretórios temporários: outputs públicos e locais, históricos e
dados do site. Só foram excluídos timestamps e proveniência da implementação
(versão de análise, commit e estado do worktree). CSV, classificações,
estimativas, todas as 26 geografias, diagnósticos, definições, datas e conteúdo
analítico dos relatórios permaneceram iguais. Os snapshots e históricos tracked
não foram alterados.

O filtro exato de município Airbnb e a omissão de métricas no script separado
que regenera relatórios são comportamentos existentes a rever em `TODO.md`.
