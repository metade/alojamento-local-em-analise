# Trabalho a retomar

- [ ] Rever a localização de `lib/alojamento_local/overlap.rb`. Este helper calcula a
  geometria dos diagramas de Venn da homepage e das freguesias; pertence à
  apresentação do site. Considerar movê-lo para junto dos helpers de construção
  do site, atualizando os imports e mantendo os testes de proporções e casos
  limite. Manter a implementação atual por agora; não está prevista a troca
  por uma biblioteca de gráficos.

- [x] Consolidar a preparação dos dados usada pela análise e por
  `RegistrationMetrics`. Fontes preparadas uma vez por execução, entradas RNAL
  preservadas e lookup de classificação derivado separadamente. Contagens de
  anúncios e aliases partilhados; agregados reutilizados pelos CSV e relatórios.
  Equivalência verificada com as fontes datadas de setembro, incluindo outputs
  locais, métricas, histórico e dados do site. Ver `docs/pipeline.md`.

- [ ] Rever os dois filtros de município Airbnb. A preparação reconhece Lisboa
  com normalização, mas o filtro seguinte exige a grafia exata `Lisboa`.
  As linhas excluídas pelo segundo filtro ainda entram nas contagens de reutilização
  de licença. Preservado na refatorização 3.1.1; corrigir separadamente com testes
  e avaliação do impacto metodológico.

- [ ] Rever `scripts/regenerate_public_report.rb`: a regeneração atual omite
  a secção de métricas de registo presente no relatório original. Preservado
  nesta refatorização; recuperar as métricas validadas do snapshot ao regenerar.

- [ ] Considerar integrar `scripts/reanalyse_public_run.rb` numa opção de
  `run_me.rb` para analisar as fontes de um run público anterior. Preservar a
  seleção das fontes datadas através do metadata, a verificação dos hashes
  SHA-256, a validação antes da substituição e a preservação dos outros pares de datas; usar o pipeline existente com as
  versões atuais, sem descarregar fontes novas. Atualizar documentação e testes
  se o wrapper separado for substituído.
