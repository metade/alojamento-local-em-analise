# Agent and contributor guide

## Project purpose

This project compares Airbnb listing snapshots for Lisbon with the official Portuguese local-accommodation register. It identifies licence matches, formatting mismatches, possible repeated use of licence numbers, and listings whose apparent location differs from the official record.

The analysis is investigative. A result is an indicator for verification, not a legal finding that a listing or establishment is illegal.

## Running the project

Install dependencies:

```bash
bundle install
```

Update sources, then run the analysis:

```bash
bundle exec rake sources:update
bundle exec rake analysis:local
```

Source updates, analysis and site builds are independent. `sources:update` checks the latest Lisbon Airbnb snapshot and downloads missing files; it refreshes RNAL only when no dated copy exists or its download date is older than the Airbnb snapshot. Analysis tasks select the latest dated local files without network requests. `refresh` runs source updates, public analysis and the site build; `rebuild` runs public analysis and the site build without source updates. The default analysis mode is `local`, creating an immutable detailed run under:

```text
data/private/<airbnb-snapshot-date>__<official-download-date>/
```

Local runs are immutable. Each repeated local analysis automatically creates a timestamped sibling rerun, preserving previous results. Analysis always recalculates from local sources and has no force or reuse option. `FORCE=1` applies only to `sources:update` (including the source stage of `refresh`), downloading both sources again. `rebuild` never downloads sources, even with `FORCE=1`.

Use the explicit public mode to create sanitised, publishable outputs:

```bash
bundle exec rake analysis:public
```

Public runs are created under:

```text
data/snapshots/<airbnb-snapshot-date>__<official-download-date>/
```

Public outputs use one folder per dated source pair. Reanalysis validates new outputs before replacing that folder and its history rows; Git retains previously committed versions. Other date pairs remain unchanged. Local runs remain immutable. Each analysis invocation recalculates. `REUSE_EXISTING` is no longer used. Reanalysis replaces public outputs for the same dated source pair after validation; repeated local analysis creates a preserved sibling rerun. Changed source hashes for an existing public date pair remain rejected.

Local runs contain the same aggregate `snapshot.json` schema with local mode and rerun IDs, plus `listings_detailed.csv` and `licence_groups_detailed.csv` for diagnostics. Local runs are ignored by Git. Public runs contain only authoritative `snapshot.json` (schema 6.0.0). No separate CSV/JSON downloads are generated. The loader also reads consolidated schema 5.0.0 without its former exports and legacy split-file schema 4.0.0 with supported registration metrics; a present consolidated document is always authoritative. Publication validates its schema, provenance and aggregates. Existing public source hashes are verified before replacing a dated run. Analysis is data-only. `site:build` and `report:build[run_dir]` always generate completed HTML and PDF using the bundled `wkhtmltopdf-binary`; there is no fallback. Standalone outputs default to `tmp/reports/public/<run-id>/` or `tmp/reports/local/<run-id>/`, overridden by `DESTINATION`. Report destinations must be separate output directories. Local input directories remain immutable; older local runs without `snapshot.json` require a new analysis rerun. Public history in `data/history/` keeps the current summary and auxiliary rows for each dated source pair, replacing only that pair on reanalysis. Local history in `data/private/history/` is append-only.

Run the full test suite (`bundle exec rake` also runs it by default):

```bash
bundle exec rake test
```

Ruby syntax checks:

```bash
ruby -c Rakefile
ruby -c lib/alojamento_local/analysis.rb
ruby -c site/_plugins/site_data.rb
ruby -c site/_plugins/report_pages.rb
ruby -c lib/alojamento_local/site_checker.rb
ruby -c lib/alojamento_local.rb
ruby -c lib/alojamento_local/analysis/data.rb
```

## Data and reproducibility

Raw data under `data_sources/**/*.csv`, detailed local results under `data/private/`, and cached files under `tmp/` are intentionally ignored by Git. Transformed, versioned outputs under `data/snapshots/` and `data/history/` are publishable project outputs and may be committed. Snapshot documents and legacy CSVs are aggregate-only and must not contain listing/host identifiers, listing URLs, names, addresses, exact coordinates, or raw licence strings. Do not commit large raw upstream datasets.

The GitHub Actions workflow in `.github/workflows/monthly-analysis.yml` runs monthly or through `workflow_dispatch`, tests before source updates and analysis, restores the latest retained `analysis-sources` artifact from a successful default-branch run, runs `sources:update`, archives only the latest dated pair with 90-day retention renewed each run, explicitly selects `analysis:public`, stages and audits only the sanitised `data/snapshots/` and `data/history/` outputs before committing them, builds the site from public snapshots, and publishes the site as a GitHub Pages artifact. Sources may be reused, but analysis always recalculates, even when the dated pair is unchanged. It must never commit local/detailed outputs or the generated site.

The `.github/workflows/site-publish.yml` workflow rebuilds and publishes the site on human pushes to `main` and through `workflow_dispatch`. It skips the automated `github-actions[bot]` / `Atualiza análise mensal` push because the monthly workflow already builds and publishes the site in that same run. Site publication is therefore separate from the data-analysis decision, while both use `bundle exec rake site:build` and the publication audit.

Rake is the interface for analysis, site builds and site checks; its tasks require `lib/alojamento_local.rb` inside the task and call `Analysis.run`, `SiteChecker` or the standard `jekyll build` CLI. The entry point configures Zeitwerk to load project constants from matching file paths. Keep standard-library and gem requires explicit; do not require individual project files. `public_schema.rb` defines shared constants and is explicitly required outside the loader. `test/alojamento_local_test.rb` checks eager loading for filename/constant consistency. npm provides frontend tooling through `npm run site:css`. Use `bundle exec rake -T` to list tasks. `bundle exec rake site:build` builds from existing public snapshots without running the analysis. `bundle exec rake site:check` checks the generated site. Test files load the application in the separate process launched by `Rake::TestTask`.

Before committing changes to `data/snapshots/`, `data/history/`, or publication workflows, run `ruby scripts/audit_publication.rb`. Run `ruby scripts/audit_publication.rb --history` when auditing repository history. A history rewrite requires a recoverable Git backup and coordinated approval before force-pushing.

The Airbnb snapshot is discovered from the public Inside Airbnb data page at runtime. `latest_airbnb_snapshot` must select the latest Lisbon `listings.csv.gz` entry and fail clearly if the page format changes. The run ID uses the date in the source filename, rather than assuming that the maximum listing-level `last_scraped` date is the archive date.

A fresh official register is downloaded with the actual current date in its filename only when needed for the Airbnb snapshot. Cached RNAL files retain their original download date. Analysis uses the latest dated local copy, never an undated file. The `metadata` section of `snapshot.json` records source URLs, source dates, SHA-256 hashes, Git commit, analysis version, methodology version, and output schema version.

Airbnb `last_scraped` values are listing-level collection dates and may span several days. They are not necessarily the same as the archive snapshot date.

Historical comparisons are generated only for metrics with the same methodology version. Comparisons across different methodology versions are marked incompatible. Reanalysis replaces the current public output for its dated source pair; previously committed results remain available through Git.

## Analysis architecture

`Analysis.run` is the orchestration entry point. It validates the mode, prepares sources, selects the destination, calculates results, and generates data inside the publication step. It returns `{run_id:, path:, summary:}`. Supply both source paths or neither; omitting them selects the latest dated local pair. There is no separate `Runner` or facade for internal helpers.

- `Analysis::PreparedSources::Pair` owns source selection, preparation, dates, URLs, initial hashes, byte-change verification and the base source-date `identifier`. Local rerun suffixes depend on output-directory state and remain in `Analysis`.
- `Analysis::Classifier` produces detailed classified listing rows from that prepared pair. `Aggregates`, `AnnouncementCounts` and `RegistrationMetrics` calculate their respective aggregates without selecting or downloading sources.
- `Analysis::Result` takes `sources`, `run_id` and `mode`; it owns classified listings, aggregates, summary and run metadata. Its `snapshot` builds and validates the existing immutable `PublicSnapshot` representation. The matched `official_register_date` is derived from classified listings here; the official download date belongs to source provenance.
- `Analysis::OutputWriter` is an instance holding a result and output path. Its generation methods own the shared snapshot document and local diagnostic CSVs; serialization helpers are private.
- `Analysis::History` owns comparisons and history CSV operations. `Analysis::PublicPublisher` stages and validates the public run and its histories, installs them together, rolls back failures or interruptions, and cleans staging files.

Use the responsible collaborator directly in scripts and focused tests rather than adding forwarding methods to `Analysis`. Keep the high-level sequence readable in `Analysis.run`, with setup details in private helpers. Structural refactors preserve the synthetic fixture's analytical results and output contents.

Reports share the complete Jekyll page `site/report.html`, with `layout: null`.
Analysis writes the same `snapshot.json` fields and schema for public and local
runs; local metadata retains local mode and rerun IDs. Only public runs enter the
site. Normal Jekyll hooks prepare `site.data.site` in `post_read`; the report
generator loads snapshots through `PublicSnapshot::Loader` and creates pages
before rendering. After Jekyll writes HTML, `post_write` copies aggregate downloads
and calls `ReportPdf` using bundled wkhtmltopdf. Rake invokes `jekyll build`, then
checks and audits its output. Direct Jekyll builds also generate report PDFs.
`report:build` uses the same build path with only report pages enabled. Presentation
defaults and bar widths belong in the page. `SiteChecker` verifies output files
and report/download links. Jekyll handles Liquid syntax errors. Data and privacy
validation belong to the publication audit; report tests cover calculations,
escaping, historical defaults and equivalent rendering between build modes.
Builds write directly to their destination; failures abort and may leave partial
outputs. Source snapshots and histories remain unchanged. Data publication still
uses `Analysis::PublicPublisher` with validation and rollback. Stored historical
reports are retained but ignored during builds. Standalone public builds copy
only allowlisted data files; local builds expose no diagnostic downloads.
Unsupported archives retain data downloads but require verified reanalysis for reports.

## Matching and classification

Licence values are normalized conservatively. Leading zeroes and clear `/AL` or legacy year formats may be normalized; other schemes such as `/UT/YYYY` must not be treated as AL registration numbers.

Repeated licence numbers are not automatically collapsed. The classifier uses spatial clusters within 500 metres, listing names, room/property types, official establishment type, and official municipality. `host_id` may exist in in-memory/local analysis rows as diagnostic metadata, but is not used as a merge criterion and must never be written to public outputs.

The output distinguishes, among other categories:

- likely establishments with multiple room/unit listings;
- repeated licences in the same location;
- the same licence appearing in multiple locations;
- licences officially registered outside Lisbon;
- listings with no identifiable licence.

The establishment-level figure printed by the script is an analytical estimate. It collapses only the lower-risk repeated-location categories and leaves suspicious reuse cases separate.

## Editing guidance

Track deferred work in [TODO.md](TODO.md).

### Registration statistics

Measured overlap metrics live in the `registration_metrics` section of versioned `snapshot.json` (metric version 1.0.0). See [README.md — Métricas de registo](README.md#métricas-de-registo) and each output's `definitions` for units and limitations. Preserve the homepage and district layout and keep each district RNAL headline consistent with its overlap total.

- RNAL and Airbnb sets count distinct normalized AL numbers; announcement counts and official entry counts have separate fields. Never sum parish distinct counts to obtain Lisbon.
- Use official Concelho/Freguesia for RNAL and observed geography for Airbnb. Retain unknown geography explicitly and qualify local set differences.
- Public run IDs contain only the two source dates. Versions live in metadata. Analysis always recalculates; replacing an existing public pair verifies its source hashes and validates the new schema, provenance and aggregates before installation.
- To reproduce a prior run with a new methodology from verified local dated sources: `bundle exec ruby scripts/reanalyse_public_run.rb <prior-public-run-id>`. Never relabel an old source as a fresh download.
- Circle areas and overlap use measured sets, including empty, disjoint, identical and contained sets. Announcement bubbles use a separate fractional scale.
- Regression metric/geometry tests in `test/registration_metrics_test.rb` also run through `test/versioned_analysis_test.rb`.

### Source preparation and methodology changes

- Prepare sources once per run with `Analysis::PreparedSources::Pair`; no cache by filename. Preserve every official entry and its raw fields. Derive the classification lookup separately so resolving official conflicts never changes the entries used by metrics.
- Retain Airbnb rows whose municipality normalizes to Lisboa. Derive reuse counts from those same retained entries; classification, spatial grouping and metrics must use the same population. Preserve original source values internally.
- Use the synthetic pipeline fixture for full public/local output regression. Update its expected files only for an intentional change, review the diffs and independently check the accounting described in [test/fixtures/pipeline/README.md](test/fixtures/pipeline/README.md).
- Record the methodology version on every run and explain changes and measured impact on identical source bytes in README's methodology notes. Keep implementation details that do not change results under the analysis version. Deferred simplification and archive work belongs in TODO.md.

### General guidance

- Format source HTML/Liquid templates with `npm run site:format` and check them with `npm run site:lint`. Prettier's Liquid plugin uses two-space indentation and a preferred width of 100 characters. CI checks source templates only; do not format archived snapshots or generated `_site/` files.

- Follow the homepage and freguesia pages for site UX: Tailwind utilities, existing design tokens, concise Portuguese copy, and qualified estimates. Keep the grouping explanation with the Airbnb figures; RNAL registrations are a separate source, not the input to that estimate.
- The district locator uses CML administrative boundaries from `site/_data/freguesia_map.json`. It highlights the selected freguesia within Lisbon; it does not show announcement locations or density.
- Preserve methodology anchors linked from other pages when simplifying `site/metodologia.html`.
- Preserve `licensa_raw` in internal analysis rows when changing licence parsing so the source value remains auditable; never write it to public outputs.
- Add regression tests for new licence formats and spatial rules.
- Do not describe unmatched or geographically inconsistent listings as illegal without official validation.
- Do not commit raw downloaded datasets unless explicitly requested.
- Treat `report.html` as the canonical self-contained report and `report.pdf` as a derivative.
- Do not recreate or maintain the removed legacy `relatorio_anomalias_al.*` files; new reports belong inside their versioned run directory.
- For homepage layout changes, run `bundle exec rake site:screenshots`. For other page layouts, build with `bundle exec rake site:build`, then run `node scripts/capture_homepage.mjs <page-path>` (for example, `freguesias/arroios/index.html` or `metodologia.html`). Inspect the 1440, 768, and 390 px images in `tmp/screenshots/`; the script checks for horizontal overflow.
