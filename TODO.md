# Trabalho a retomar

## V2 — próximos passos após o protótipo de apresentação

- [x] Contrato num único snapshot RNAL + listings originais + candidatos, fixture de teste e site/relatório HTML/PDF com UX existente.
- [ ] Rever o formato e as páginas com a fixture antes de implementar o pipeline real.
- [ ] Avaliar coordenadas vs. freguesia Airbnb, distância aos limites CML e casos de fronteira;
  definir quando atribuir freguesia e quando manter localização desconhecida.
- [ ] Gerar o snapshot único a partir das fontes, incluindo totais originais de listings: declarações de vários números,
  candidatos sem número, agrupamento conservador e reutilização em localizações separadas.
- [ ] Preparar um único registo RNAL por número AL, resolvendo duplicações na fonte sem
  selecionar arbitrariamente entre dados contraditórios. Comparar o candidato com o seu
  registo oficial e calcular `official_match.distance_km`. Definir evidência para futuras
  avaliações de correspondência e isenção.
- [x] Diagrama com todos os candidatos no total Airbnb, candidatos com número AL na
  sobreposição e candidatos sem número na área exclusiva Airbnb; sem bolha separada.
  Números repetidos contam por candidato, independentemente da avaliação RNAL.
- [x] Distribuição NUTS II de listings com registo fora de Lisboa a partir de `official_match.district`,
  contando IDs distintos e mantendo regiões em falta ou contraditórias por resolver.
- [x] Distribuição de distâncias por número AL repetido, usando a maior distância de um candidato ao RNAL;
  headline em listings distintos, intervalos até 500 m, 500 m–1 km, 1–2 km, 2–5 km e mais de 5 km.
- [ ] Capacidade fica para uma etapa posterior.
- [ ] Substituir a orquestração antiga e os workflows de publicação pelo novo pipeline;
  retirar histórico, snapshots/relatórios antigos e utilitários de apresentação sem uso.
  Trocar a seleção de fixture em `_config.yml` pelo snapshot real em `data/snapshots/candidate/`.

As tarefas abaixo referem-se ao sistema anterior e serão revistas ao substituir o pipeline.

## Primeiro lançamento e arquivo de fontes

Prioridade: publicar uma primeira análise com o par de fontes atual. Guardar as
fontes agora; adiar comparações e integração do arquivo. Manter a identificação
da metodologia e a explicação do método atual, mesmo ao simplificar o sistema.

Os artefactos `analysis-sources` do workflow mensal conservam apenas o último
par para reutilização entre execuções, com retenção de 90 dias renovada em cada
run. A recuperação de fontes históricas após expiração continua a depender do
arquivo permanente e da integração descrita abaixo.

1. [x] Fazer backup no Google Drive das fontes datadas Airbnb e RNAL existentes.
   Preservar os bytes originais em ficheiros comprimidos, nomes/datas e um
   manifesto com SHA-256, tamanhos, contagens e URLs das fontes. Verificar os
   hashes após restaurar o backup. Registar a localização no Drive e confirmar
   o upload antes de considerar esta tarefa concluída; conservar fontes locais.
   ZIPs preparados em `tmp/source-backup-2026-10-12/`: `q4-2025.zip` (Airbnb
   setembro + RNAL novembro) e `q3-2026.zip` (Airbnb junho + três dumps RNAL
   setembro), com manifestos e hashes de restauro verificados. Upload manual
   confirmado pelo utilizador; os rótulos trimestrais não alteram datas das fontes.
   Arquivo público reduzido aos pares `2025-09-21__2025-11-25` (Q4 2025) e
   `2026-06-23__2026-09-26` (Q3 2026), reanalisados no schema consolidado 6.0.0
   após verificação dos hashes do manifesto; restantes runs públicos removidos.
2. [ ] Simplificar o sistema para o primeiro lançamento com dados atuais:
   remover comparações históricas, seleção/fallback de metodologias antigas e
   infraestrutura de histórico do pipeline, site, workflows e testes. Rever os
   snapshots de desenvolvimento existentes antes de escolher o primeiro
   baseline. Preservar `methodology_version`, datas, hashes e proveniência nos
   resultados; manter a página de metodologia e os seus anchors. Atualizar
   documentação e AGENTS.md para refletir o fluxo simplificado.
3. [ ] Reintroduzir comparação histórica a partir de fontes arquivadas locais.
   Escolher explicitamente os pares de fontes e executar ambos com a mesma
   metodologia para medir mudanças no tempo. Para medir o efeito de uma mudança
   metodológica, usar os mesmos bytes das fontes nas duas versões do método.
   Guardar resultados distintos por fontes e versão, sem substituir a referência
   anterior; mostrar datas Airbnb/RNAL separadamente e investigar diferenças de
   cobertura do export RNAL antes de interpretar quedas como encerramentos.
4. [ ] Acrescentar recuperação de fontes arquivadas do Google Drive ao fluxo
   anterior, depois de validar a comparação local. Usar IDs/URLs explícitos,
   autenticação adequada para ficheiros privados, secrets fora do repositório,
   cache local e verificação SHA-256 antes da análise. O build normal do site
   continua a consumir outputs sanitizados; só o fluxo explícito de reanálise
   histórica deve precisar do arquivo e das credenciais.

- [ ] Antes do primeiro lançamento, estabelecer o baseline de metodologia e
  manter notas curtas por versão: o que mudou, porquê e efeito nos números
  quando aplicado às mesmas fontes. Associar essas notas à versão registada no
  run. A preservação de múltiplos resultados por versão fica para a etapa 3;
  um rótulo no metadata, sozinho, não preserva resultados substituídos.

## Pipeline unificado

- [x] Remover os modos local/público da análise. Gerar sempre um snapshot agregado
  e diagnósticos privados separados. O Jekyll gera ambos os relatórios com o
  template partilhado. Retirar modo e IDs de rerun
  do schema 7.0.0; preservar metodologia e resultados em fontes idênticas.
- [x] Usar o flag nativo `serving` do Jekyll para incluir relatórios privados e
  links no build local, a partir dos CSVs disponíveis. Builds normais removem e
  excluem esses outputs; a auditoria rejeita dados/links privados na publicação.
  Sem servidor próprio, interceptação HTTP ou renderer ERB separado.

## Outras tarefas

- [x] Mover o helper de geometria dos diagramas de Venn para
  `lib/alojamento_local/site_data/overlap.rb`, sob `SiteData::Overlap`.
  Preservar a implementação e o componente Liquid existente; manter os testes
  de proporções e casos limite em `test/site_data_overlap_test.rb`.

- [x] Introduzir um loader partilhado de snapshots públicos para a regeneração
  do relatório e a construção do site. Ler os ficheiros atuais e devolver uma
  estrutura com interface estável para metadata, resumo, grupos de licenças,
  anúncios por freguesia e classificação, totais por freguesia e métricas de
  registo. Centralizar a validação de schema, proveniência e coerência dos
  agregados; manter explícitas as unidades e usar nomes sem ambiguidades.
  Migrar os consumidores para essa interface e testar a equivalência dos
  relatórios e dados do site com a fixture sintética, sem alterar os outputs.

- [x] Gerar os relatórios por snapshot através de uma página completa
  do Jekyll, com `layout: null`, consumindo os dados validados pelo loader partilhado. Incorporar
  estilos e os restantes recursos necessários para manter `report.html`
  autónomo, utilizável offline e como fonte do PDF derivado. Gerar os relatórios
  no build do site, incluindo a publicação no GitHub, e acrescentar uma tarefa
  Rake que use a mesma fonte e o mesmo gerador Jekyll para publicar apenas o
  relatório de um snapshot, sem construir as páginas editoriais.
  Definir o destino do HTML e adaptar a análise, a regeneração, as verificações
  de reutilização e a auditoria à nova etapa de geração; manter os builds do
  site sem alterações aos snapshots versionados. Substituir a montagem HTML
  de `Report` em Ruby e testar a equivalência entre os dois modos de build,
  as secções e métricas preservadas e o funcionamento autónomo do relatório.

- [x] Depois do loader partilhado, consolidar os dados do snapshot num ficheiro
  estruturado e versionado que esse loader consuma. Manter a interface do
  documento para o relatório e o site. Apenas schema 7.0.0: snapshots anteriores
  exigem reanálise das fontes verificadas; sem leitores legados ou fallback.
  Validar a estrutura com JSON Schema e a proveniência/contabilidade em Ruby.
  Atualizar a escrita, o schema
  público, a auditoria de publicação e a
  documentação; rejeitar formatos antigos e verificar a equivalência dos resultados.

- [x] Integrar a reanálise de um run público anterior em `analysis[run_id]` e
  remover o wrapper separado. Selecionar fontes datadas pelo metadata, verificar
  ambos os hashes SHA-256 e usar o pipeline existente com as versões atuais, sem
  downloads. Preservar validação, substituição transacional, relatórios arquivados
  e outros pares de datas; atualizar documentação e testes.
