# Publicação segura dos relatórios

Este plano separa a análise detalhada local da publicação de resultados agregados. O objetivo é tornar possível publicar relatórios úteis sem incluir datasets brutos, identificadores de anfitriões, endereços, coordenadas exatas ou outros dados potencialmente pessoais.

## Princípios

- O modo local deve ser o modo predefinido para proteger a investigação detalhada; a publicação requer `--mode public` explícito.
- Dados brutos e resultados detalhados permanecem locais e são ignorados pelo Git.
- A publicação contém apenas resultados derivados, agregados e anonimizados.
- Exemplos de anomalias devem ser ilustrativos ou agregados, não identificáveis.
- A linguagem descreve sinais e questões para verificação, não ilegalidade ou culpa.
- Atribuímos corretamente Inside Airbnb e Turismo de Portugal/RNAL.

## Sessão 1 — Mapear e limpar o fluxo de dados ✅ concluída (2026-09-18)

Objetivo: tornar explícita a fronteira entre dados locais e outputs publicáveis.

Tarefas concluídas:

- [x] Inventariar inputs, downloads, caches, ficheiros intermédios e outputs.
- [x] Separar conceptualmente as áreas. Até à implementação dos modos público/local, os outputs sanitizados permanecem em `data/snapshots/`; dados detalhados e fontes continuam locais/ignorados.

  ```text
  data_sources/       downloads brutos locais, ignorados
  tmp/                caches locais, ignorados
  data/private/       resultados detalhados locais, ignorados
  data/public/        resultados sanitizados publicáveis
  data/snapshots/     apenas snapshots sanitizados commitados
  ```

- [x] Garantir que os dados brutos nunca são copiados diretamente para outputs commitados.
- [x] Definir schemas explícitos para os CSVs públicos.
- [x] Remover dos outputs públicos:
  - `host_id`;
  - IDs e URLs de anúncios;
  - nomes e títulos;
  - coordenadas exatas;
  - endereços;
  - strings de licença originais;
  - texto arbitrário proveniente da fonte.
- [x] Corrigir o `.gitignore` para abranger ficheiros em subdiretórios de `data_sources/`.
- [x] Acrescentar validação e testes que falham se outputs públicos contiverem colunas proibidas ou URLs.

Critério de conclusão: cumprido. Uma execução nova produz apenas ficheiros agregados/sanitizados em `data/snapshots/`; o snapshot existente também foi sanitizado. A validação cobre os três CSVs públicos e o metadata público.

Nota: a auditoria do histórico Git fica deliberadamente para a Sessão 2; a conclusão desta sessão refere-se aos ficheiros atualmente presentes na árvore de trabalho.

## Sessão 2 — Auditar o histórico Git ✅ concluída localmente (2026-09-18)

Objetivo: confirmar que dados pessoais anteriormente commitados não continuam acessíveis no histórico.

Resultado da auditoria e limpeza local:

- O histórico alcançável foi pesquisado em `main` e `origin/main`.
- Foram encontrados dados detalhados em commits anteriores, incluindo o ficheiro `data_sources/data_transformed/result.csv`, `host_id`, coordenadas e strings de licença brutas.
- O remoto configurado é `git@github.com:metade/Alojamento_Ilegal.git`; por isso, o histórico foi tratado como potencialmente partilhado.
- O ficheiro detalhado foi removido do índice atual, preservando a cópia local ignorada.
- A história local foi reescrita para remover o ficheiro detalhado de todos os commits e o snapshot pré-sanitização.
- Foi criada uma cópia de segurança em `/private/tmp/Alojamento_Ilegal-before-history-rewrite.bundle` antes da reescrita.
- `scripts/audit_publication.rb --history` reproduz a auditoria sem imprimir valores pessoais.
- `.github/workflows/publication-audit.yml` impede a reintrodução de ficheiros locais/detalhados ou campos proibidos nos outputs publicáveis.

Nota sobre o remoto:

- O remoto GitHub foi atualizado com `git push --force-with-lease`; `origin/main` aponta agora para a história limpa.

- Pesquisar todos os commits, branches e tags por:
  - `host_id`;
  - URLs Airbnb;
  - coordenadas;
  - endereços;
  - nomes;
  - `result.csv`;
  - strings de licença brutas.
- Confirmar se o repositório já foi partilhado com terceiros.
- [x] Se o histórico ainda for privado e descartável, reescrevê-lo para remover os ficheiros sensíveis.
- [x] Fazer uma cópia de segurança antes de qualquer reescrita.
- [x] Avaliar o risco do histórico partilhado; a publicação da história limpa requer force-push coordenado ou um repositório público novo.
- [x] Acrescentar uma verificação CI que impeça a reintrodução desses dados.

Critério de conclusão local: cumprido. `ruby scripts/audit_publication.rb --history` termina com sucesso para todos os refs locais alcançáveis.

## Sessão 3 — Modos público e local ✅ concluída (2026-09-18)

Objetivo: permitir relatórios anónimos no GitHub Actions e investigação detalhada local.

Interface proposta:

```bash
bundle exec ruby run_me.rb --mode public
bundle exec ruby run_me.rb --mode local
```

Regras:

- `local` é o modo predefinido; `public` requer seleção explícita.
- GitHub Actions chama explicitamente `--mode public`.
- `local` escreve resultados detalhados apenas numa área ignorada.
- O modo local pode incluir campos diagnósticos adicionais, mas nunca deve ser publicado automaticamente.
- Os dois modos usam schemas, nomes e diretórios distintos.
- O relatório indica claramente o modo e a data de geração.
- Não deve existir uma opção pública equivalente a “incluir detalhes”.

Testes necessários:

- O output público não contém campos proibidos.
- O output local contém os campos diagnósticos esperados.
- Ficheiros locais não são confundíveis com outputs publicáveis.
- A linguagem pública usa “indicador”, “possível divergência” e “requer verificação”.

Critério de conclusão: o CI não consegue publicar o modo local por engano.

Implementação concluída:

- [x] `run_me.rb` aceita `--mode public` e `--mode local`; `local` é o predefinido.
- [x] O modo público mantém os schemas agregados em `data/snapshots/` e regista `mode: public` nos outputs.
- [x] O modo local escreve ficheiros com nomes/schema distintos em `data/private/`, incluindo os campos diagnósticos necessários.
- [x] Os outputs locais e o histórico local permanecem ignorados pelo Git.
- [x] O workflow chama explicitamente `run_me.rb --mode public`.
- [x] O relatório identifica o modo e a data de geração.
- [x] Testes cobrem o modo público predefinido, a rejeição de uma opção pública de detalhes e a presença de diagnósticos no modo local.

Critério de conclusão: cumprido. O caminho executado pelo CI só seleciona o modo público; o modo local requer uma escolha explícita e escreve numa área ignorada, com nomes diferentes dos outputs publicáveis.

## Sessão 4 — Exemplos de anomalias ✅ concluída (2026-09-18)

Objetivo: explicar o método sem identificar operadores ou anúncios.

Preferir:

- exemplos sintéticos baseados nos fixtures dos testes; ou
- padrões agregados ao nível de freguesia/município.

Evitar publicar:

- números reais de licença em casos únicos;
- títulos de anúncios;
- IDs de anfitrião;
- URLs de anúncios;
- endereços;
- coordenadas exatas;
- distâncias exatas em casos únicos.

Cada exemplo deve ser marcado como `ilustrativo` ou `resultado agregado`.

Implementação concluída:

- [x] O relatório inclui cinco exemplos sintéticos: ausência de licença identificável, possíveis anúncios múltiplos do mesmo estabelecimento, repetição em localizações distintas, licença oficial fora de Lisboa e possível divergência de localização.
- [x] Cada exemplo é marcado como ilustrativo e explica uma leitura prudente, sem apresentar conclusões legais.
- [x] Os exemplos não incluem números reais de licença, títulos, IDs, URLs, endereços, coordenadas ou distâncias exatas.
- [x] O README documenta o propósito dos exemplos e a fronteira dos dados publicados.
- [x] Os testes verificam a presença da secção ilustrativa e a ausência de padrões identificáveis no relatório.

Critério de conclusão: cumprido. É possível compreender cada tipo de sinal sem identificar facilmente uma propriedade ou operador.

## Sessão 5 — Preparar o site público ✅ concluída (2026-09-18)

Objetivo: publicar um site estático com relatórios sanitizados.

Tarefas:

- Criar uma página inicial com:
  - objetivo do projeto;
  - fontes e atribuição;
  - metodologia;
  - limitações;
  - aviso de que não há conclusões legais;
  - contacto para correções;
  - datas dos snapshots.
- Publicar apenas HTML, CSVs agregados, metadata e documentação metodológica.
- Manter downloads brutos e relatórios locais fora do artefacto do Pages.
- Acrescentar `LICENSE` para o código e `NOTICE` para a atribuição dos dados.
- Rever o nome e os títulos públicos para uma linguagem inquisitiva e não acusatória.
- Decidir se o repositório permanece privado enquanto o site é público.

Implementação concluída:

- [x] `scripts/build_site.rb` monta um site estático a partir dos snapshots públicos versionados.
- [x] A página inicial documenta objetivo, fontes e atribuição, metodologia, limitações, aviso não jurídico, correções e datas dos snapshots.
- [x] Cada run publicado inclui apenas HTML, CSVs agregados e metadata; `LICENSE` e `NOTICE` acompanham o site.
- [x] O construtor não copia `data_sources/`, `data/private/` ou caches para o artefacto.
- [x] A documentação regista que o repositório pode permanecer privado enquanto um deployment separado publica `_site/`.

Critério de conclusão: cumprido. O artefacto é gerado apenas a partir de `data/snapshots/` e a auditoria de publicação confirma que os ficheiros publicáveis não contêm campos proibidos nem URLs de anúncios.

## Sessão 6 — Automatização e publicação

Objetivo: tornar segura a execução trimestral.

Tarefas:

- Alterar Actions para gerar e publicar apenas outputs públicos.
- Considerar publicar o site como artefacto/deployment, em vez de fazer commit automático de todos os outputs.
- Fixar Actions de terceiros por SHA completo.
- Reduzir as permissões do workflow ao mínimo necessário.
- Criar um gate de publicação que verifique:
  - ausência de colunas proibidas;
  - ausência de URLs e padrões de identificadores;
  - modo `public` confirmado;
  - presença de atribuição;
  - ausência de ficheiros brutos.
- Fazer uma execução completa de ensaio e inspecionar manualmente o site.
- Só depois ativar Pages e o agendamento trimestral.

Critério de conclusão: uma execução automática publica exclusivamente o artefacto sanitizado.

Implementação concluída:

- [x] O workflow trimestral executa explicitamente o modo público e faz commit apenas de `data/snapshots/` e `data/history/`, nunca de dados locais ou do site gerado.
- [x] O site é construído a partir de `data/snapshots/` e enviado como artefacto do GitHub Pages; o deployment ocorre num job separado com apenas `pages: write`, `id-token: write` e `actions: read`.
- [x] Actions de terceiros estão fixadas por SHA completo.
- [x] O gate verifica outputs públicos e o artefacto final, incluindo modo `public`, padrões de URLs/identificadores, referências a fontes locais e presença de `NOTICE`.
- [x] O ensaio local do construtor, gates, sintaxe e testes terminou com sucesso; a inspeção manual confirmou que o site contém apenas o índice, runs públicos, licença e atribuição.
- [x] A ativação efetiva do Pages/agendamento fica limitada à configuração do repositório no GitHub; o workflow está preparado para deployment por Actions.

Critério de conclusão: cumprido para o fluxo versionado e o artefacto local. A execução real no GitHub requer apenas ativar GitHub Pages com a origem “GitHub Actions”.

## Ordem recomendada

1. Fluxo de dados e schemas.
2. Auditoria e limpeza do histórico.
3. Modos público/local.
4. Exemplos e linguagem.
5. Site estático.
6. Workflow, gates e publicação.

Não ativar o GitHub Pages antes de concluir as sessões 1–5.
