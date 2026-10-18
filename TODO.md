# Trabalho a retomar

## Pipeline de candidatos

- [x] Fazer uma primeira classificação descritiva dos 5 827 anfitriões do snapshot
  de setembro por composição dos anúncios: apartamentos inteiros, quartos privados,
  mistos ou outras categorias. Rever um portefólio misto em profundidade.
- [ ] Usar perfis de anfitrião para orientar revisão de grupos anfitrião–AL–unidade,
  sem exceção global de confiança. O exemplo revisto anuncia várias unidades sob
  o mesmo AL, incluindo quartos de apartamentos com áreas e contagens semelhantes.
  Avaliar referências explícitas e convenções de nomes por unidade antes de autorizar
  novas fusões; tipo de portefólio e ausência de contradições não provam identidade.

- [x] Substituir o pipeline antigo no mesmo ponto de entrada, com snapshots em
  pastas de pares datados, manifests locais, validação de cobertura e substituição segura.
- [x] Extrair vários números explícitos, conservar declarações originais, resolver
  conflitos RNAL e calcular resumos RNAL/listings independentemente.
- [x] Comparar um único conjunto de anúncios, com procura espacial até 500 m,
  referências de unidade, declarações distintas e complete-link pontuado.
  Preservar declarações individuais, categorias mistas e medóide determinístico.
- [x] Publicar downloads datados e relatórios na raiz, selecionar a pasta mais
  recente por defeito e manter a fixture de apresentação apenas por seleção explícita.
- [x] Remover comparações, readers, expectativas, relatórios e snapshots antigos
  da árvore atual, preservando o histórico Git sem reescrita.
- [x] Usar `undetermined` para relações sem evidência suficiente de duplicação;
  distinguir a fusão de alojamentos da classificação dos anúncios como duplicados.
- [x] Resolver como apartamentos separados os conflitos de números distintos com
  declarações claras e registos RNAL de apartamentos localmente consistentes,
  sem atribuir pontos de identidade nem afirmar que partilham um edifício.
- [ ] Calibrar referências explícitas e relações de duplicados/quartos com amostra
  verificada; ampliar vocabulário apenas com regressões. Rever ambiguidades,
  anúncios de várias unidades e texto de anfitrião repetido, sem objetivo de redução
  do número de candidatos. Partilhar `Exempt` nunca estabelece identidade.
- [x] Substituir frases específicas por uma via de quartos privados e apartamento
  inteiro com o mesmo anfitrião/AL, descrição forte e proximidade. Manter conflitos
  de unidade, complete-link e contagens independentes das fontes.
- [ ] Avaliar falsos positivos da via anfitrião/AL/descrição em portefólios com
  texto-modelo e várias unidades; rever perdas de fusões apoiadas por frases.
- [x] Resolver separações de anúncios inteiros com o mesmo AL e diferenças
  simultâneas de quartos, camas e capacidade, sem referência explícita comum de
  apartamento. Diferenças isoladas mantêm revisão; o sinal de número partilhado permanece.
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
- [ ] Avaliar capacidade autorizada e correspondência RNAL com critérios e evidência
  próprios. Os atributos de capacidade servem apenas para contradizer fusões de
  apartamentos inteiros; existência nacional não pontua identidade.

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
