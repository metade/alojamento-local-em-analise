# Trabalho a retomar

- [ ] Rever a localização de `lib/al_ilegal/overlap.rb`. Este helper calcula a
  geometria dos diagramas de Venn da homepage e das freguesias; pertence à
  apresentação do site. Considerar movê-lo para junto dos helpers de construção
  do site, atualizando os imports e mantendo os testes de proporções e casos
  limite. Manter a implementação atual por agora; não está prevista a troca
  por uma biblioteca de gráficos.

- [ ] Consolidar a preparação dos dados usada pela análise e por
  `RegistrationMetrics`. Atualmente, `licensed_als` e
  `RegistrationMetrics.calculate` leem e normalizam o mesmo CSV RNAL e constroem
  índices separados; há também contagens de anúncios repetidas nos métodos de
  output e aliases de freguesias duplicados no site builder. Preparar as fontes
  uma vez e partilhar os dados entre classificação e métricas, preservando todas
  as entradas oficiais, incluindo duplicados e conflitos geográficos. Manter
  os cálculos de conjuntos em `RegistrationMetrics` e verificar que os resultados
  e as definições publicados não mudam com a refatorização.

- [ ] Considerar integrar `scripts/reanalyse_public_run.rb` numa opção de
  `run_me.rb` para analisar as fontes de um run público anterior. Preservar a
  seleção das fontes datadas através do metadata, a verificação dos hashes
  SHA-256, a validação antes da substituição e a preservação dos outros pares de datas; usar o pipeline existente com as
  versões atuais, sem descarregar fontes novas. Atualizar documentação e testes
  se o wrapper separado for substituído.
