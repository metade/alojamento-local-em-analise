# Alojamento Local em Lisboa — indicadores para verificação

Análise investigativa de snapshots de anúncios Airbnb em Lisboa comparados com o registo oficial português de alojamento local. Os resultados são indicadores para verificação oficial, não conclusões jurídicas.

## Execução

```bash
bundle install
bundle exec ruby run_me.rb
```

Por defeito, a execução é local e cria um run imutável detalhado em:

```text
data/private/<airbnb-snapshot-date>__<official-download-date>/
```

Runs locais são imutáveis. Durante o desenvolvimento, `--force` preserva o run existente e cria um novo diretório local com sufixo `__rerun-<timestamp>`:

```bash
bundle exec ruby run_me.rb --force
```

Esta opção só está disponível no modo local e não substitui nem remove resultados anteriores.

Os resultados locais incluem diagnósticos como `host_id`, coordenadas e valores de licença originais e permanecem fora do Git. Para gerar os outputs agregados publicáveis, selecione explicitamente o modo público:

```bash
bundle exec ruby run_me.rb --mode public
```

Para uma execução automatizada repetida, `bundle exec ruby run_me.rb --mode public --reuse-existing` reutiliza um run público já existente sem o reescrever e permite que a publicação do site continue.

O modo público cria o run em:

```text
data/snapshots/<airbnb-snapshot-date>__<official-download-date>/
```

Cada run contém:

- `metadata.json` — URLs, datas, hashes SHA-256, commit Git e versões;
- `summary.json` — métricas, classificações e comparações históricas;
- `listings.csv` — contagens agregadas por freguesia e classificação;
- `licence_groups.csv` — contagens agregadas por classificação e categorias oficiais;
- `freguesias.csv` — métricas por freguesia;
- `report.html` — relatório autónomo em português.

O histórico append-only está em `data/history/summary.csv`. Runs existentes nunca são sobrescritos. Para gerar também um PDF derivado, instale `wkhtmltopdf` ou `weasyprint` e execute:

```bash
GENERATE_PDF=1 bundle exec ruby run_me.rb --mode public
```

## Site público

O site estático publicável é montado a partir dos snapshots já versionados:

```bash
npm ci
npm run site:build
```

`site:build` prepara os dados do Jekyll, gera as páginas, compila o CSS,
verifica a estrutura e executa a auditoria de publicação do artefacto. Para
repetir apenas as etapas de CSS ou verificação:

```bash
npm run site:css
npm run site:check
ruby scripts/audit_publication.rb --artifact _site
```

O CSS editável está em `site/assets/css/`: `input.css` importa os tokens, as
regras de base, layout, componentes, páginas e media queries. O Tailwind gera
`_site/assets/story.css` a partir deste ficheiro; `_site/` não é fonte editável.
Jekyll não copia os ficheiros fonte CSS para o artefacto. As classes utilitárias
servem para layout e estados simples; ilustrações, fundos e composições
editoriais permanecem em CSS próprio. Veja o [checklist visual](docs/css-visual-checklist.md)
antes de alterar o aspeto do site.

O resultado fica em `_site/` e inclui apenas a página inicial, relatórios HTML,
CSVs agregados, metadata, licença e avisos de atribuição. Datasets brutos,
resultados locais e caches não são copiados. O diretório `_site/` pode ser usado
como artefacto de um deployment estático. O workflow trimestral constrói e
valida esse diretório antes de o publicar no GitHub Pages.

O site é mantido como um projeto Jekyll em `site/`: layouts e includes
partilham a estrutura HTML, as páginas Liquid tratam a narrativa editorial e
`scripts/build_site.rb` prepara os dados públicos e chama Jekyll.

Para rever alterações localmente, construa o artefacto e sirva `_site/`:

```bash
npm run site:build
python3 -m http.server 4000 --directory _site
```

Abra `http://localhost:4000`. Depois de editar apenas CSS, execute
`npm run site:css` e atualize a página. Depois de editar templates ou dados,
execute `npm run site:build` e atualize a página.

O workflow de GitHub Pages define automaticamente a base `/alojamento-local-em-analise`.

## Testes

```bash
ruby -Itest test/al_ilegal_test.rb
ruby -Itest test/spatial_clusters_test.rb
ruby -Itest test/versioned_analysis_test.rb
```

Antes de publicar ou rever alterações aos outputs, execute a auditoria de publicação:

```bash
ruby scripts/audit_publication.rb
ruby scripts/audit_publication.rb --history
```

O primeiro comando verifica os ficheiros publicáveis na árvore atual; o segundo verifica todos os commits e refs alcançáveis.

## GitHub Actions

`.github/workflows/quarterly-analysis.yml` permite execução trimestral e manual. O workflow executa os testes, descarrega as fontes, chama explicitamente `run_me.rb --mode public`, publica os outputs versionados no repositório e guarda artefactos temporários para debugging.

`.github/workflows/publication-audit.yml` executa automaticamente a verificação de segurança dos outputs em pushes e pull requests.

O repositório pode permanecer privado enquanto um deployment separado publica o
conteúdo sanitizado de `_site/`.

O workflow trimestral faz commit apenas dos outputs públicos sanitizados em `data/snapshots/` e `data/history/`; o site é publicado como artefacto separado através do GitHub Pages, depois de executar testes, construir o site e passar os gates de publicação. Os snapshots commitados e o histórico são a fonte permanente do projeto. Datasets brutos em `data_sources/`, resultados detalhados em `data/private/` e caches em `tmp/` continuam fora do Git por defeito. Os CSVs dos snapshots são agregados e não contêm identificadores de anúncios, anfitriões, nomes, endereços, coordenadas ou valores de licença individuais.

O workflow `.github/workflows/site-publish.yml` reconstrói e publica o site em pushes humanos para `main` e através de `workflow_dispatch`. Está protegido contra o commit `Atualiza análise trimestral` produzido pelo workflow trimestral, que já constrói e publica o site na própria execução.

## Dados e método

As fontes são o arquivo público [Inside Airbnb](https://insideairbnb.com/get-the-data/) e o registo oficial disponibilizado pelo Turismo de Portugal. Em cada execução, o downloader descobre na página do Inside Airbnb o snapshot mais recente disponível para Lisboa; `last_scraped` é uma data ao nível do anúncio e pode abranger vários dias.

As licenças são normalizadas de forma conservadora. O analisador distingue, entre outras categorias:

- licença/listagem única;
- provável estabelecimento com múltiplos quartos ou unidades;
- licença repetida na mesma localização;
- mesma licença em várias localizações;
- licença oficial fora de Lisboa;
- campo de licença vazio;
- valor de licença não identificável como AL.

`host_id` pode ser usado apenas durante a análise local como metadado, nunca como critério de agrupamento; não é escrito nos outputs públicos. A estimativa de estabelecimentos colapsa apenas categorias de menor risco e mantém casos de possível reutilização separados para verificação.

### Exemplos de sinais

O relatório inclui uma secção de exemplos ilustrativos, baseada em padrões sintéticos dos testes, para explicar a leitura das classificações sem expor casos individuais. Abrange ausência de licença identificável, possíveis anúncios múltiplos do mesmo estabelecimento, repetição de licença em localizações distintas, registo oficial fora de Lisboa e possível divergência de localização.

Estes exemplos não contêm números reais de licença, nomes, IDs, URLs, endereços, coordenadas ou distâncias exatas. Os resultados publicados são agregados ao nível de freguesia/classificação e devem ser tratados como indicadores para verificação, nunca como conclusões legais.

Para instruções de manutenção e interpretação, consulte [`AGENTS.md`](AGENTS.md).
