# Trabalho a retomar

## Pipeline de candidatos

- [x] Substituir o pipeline antigo no mesmo ponto de entrada, com snapshots em
  pastas de pares datados, manifests locais, validação de cobertura e substituição segura.
- [x] Extrair vários números explícitos, conservar declarações originais, resolver
  conflitos RNAL e calcular resumos RNAL/listings independentemente.
- [x] Agrupar por evidência pontuada, complete-link até 100 m e medóide determinístico.
  Manter isenções e restantes anúncios sem número em candidatos individuais.
- [x] Publicar downloads datados e relatórios na raiz, selecionar a pasta mais
  recente por defeito e manter a fixture de apresentação apenas por seleção explícita.
- [x] Remover comparações, readers, expectativas, relatórios e snapshots antigos
  da árvore atual, preservando o histórico Git sem reescrita.
- [ ] Investigar agrupamento de candidatos sem número com evidência adequada,
  incluindo declarações de isenção. Partilhar o rótulo `Exempt` nunca estabelece
  uma relação de agrupamento. Avaliar a redução do total estimado de candidatos
  após revisão destas regras, mantendo distintos os totais de candidatos e de
  números AL na visualização.
- [ ] Investigar fiabilidade da geografia Airbnb não verificada, deslocação ou
  imprecisão das coordenadas, proximidade dos limites CML e casos de fronteira.
  Validar os polígonos completos, qualidade/época das fontes e regras para eventual
  atribuição alternativa de freguesia; não substituir já a unanimidade Airbnb.
- [ ] Investigar evidência de localização e fiabilidade RNAL, campos contraditórios,
  distância aos limites e critérios para avaliações futuras de correspondência.
  A existência nacional de um número não valida a identidade do alojamento.
- [ ] Avaliar isenções declaradas com critérios e fontes adequadas; o pipeline
  atual regista apenas a declaração, sem conclusão legal. Definir critérios e evidência
  antes de separar isenções corretas/incorretas na barra; até lá, todas ficam por verificar.
- [ ] Rever exemplos de quartos/apartamentos e calibrar regras com amostra
  verificada; pontuações são evidência e não probabilidades. Preservar regressões
  sintéticas equivalentes sem expor nomes, descrições ou anfitriões.
- [ ] Capacidade permanece adiada.

- [x] Manter um único relatório HTML/PDF e retirar diagnósticos persistidos e
  toda a geração de outputs privados.

## Arquivo e futuro histórico

- [x] Backup manual confirmado das fontes datadas no Google Drive. ZIPs preparados
  em `tmp/source-backup-2026-10-12/` (`q4-2025.zip` e `q3-2026.zip`), com manifestos
  SHA-256 e restauro verificado. Rótulos trimestrais e datas do backup não são datas
  de download das fontes; manifestações novas conservam fetch desconhecido como null.
- [ ] Definir arquivo permanente de CSVs e manifestos; artefactos CI atuais conservam
  só o último par, com retenção renovada de 90 dias.
- [ ] Reintroduzir comparações apenas mediante seleção explícita de fontes
  arquivadas e aplicação do mesmo método aos mesmos bytes. Investigar cobertura
  RNAL antes de interpretar quedas como encerramentos. Não restaurar leitores
  antigos nem comparações automáticas durante esta etapa.
- [ ] Integrar eventual recuperação autenticada do Google Drive com IDs explícitos,
  secrets fora do Git e verificação SHA-256. Builds normais continuam a consumir
  apenas snapshots locais já gerados.
