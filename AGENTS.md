# Agent and contributor guide

## Project purpose

This project compares Airbnb listing snapshots for Lisbon with the official Portuguese local-accommodation register. It identifies licence matches, formatting mismatches, possible repeated use of licence numbers, and listings whose apparent location differs from the official record.

The analysis is investigative. A result is an indicator for verification, not a legal finding that a listing or establishment is illegal.

## Running the project

Install dependencies:

```bash
bundle install
```

Update sources, then run the single analysis pipeline:

```bash
bundle exec rake sources:update
bundle exec rake analysis
```

Source updates, analysis and site builds are independent. `sources:update`
checks the latest Lisbon snapshot and refreshes RNAL only when needed. Analysis
without arguments always recalculates the latest dated local source pair without
network requests.
`bundle exec rake 'analysis[2026-06-23__2026-09-26]'` loads that existing snapshot
through `PublicSnapshot.load_run` (which delegates to `load`).
`Analysis::Data.local_paths_for_snapshot!` selects local dated sources from its
metadata and verifies both SHA-256 hashes before the task calls `Analysis.run`
with current versions.
Invalid/unknown IDs, missing sources and mismatched hashes fail before analysis.
`refresh` updates sources, analyses and builds the public site; `rebuild` analyses
and builds without downloads. `FORCE=1` applies only to source updates.

There are no local/public analysis modes, mode metadata or rerun IDs. Every run
writes aggregate-only `snapshot.json` under `data/snapshots/<source-date-pair>/`
and detailed CSVs under ignored
`data/private/<source-date-pair>/`. Reanalysis replaces both outputs and that
pair's history rows together, with staging, validation and rollback. Other pairs
remain unchanged. Existing public source hashes must match before replacement.
No private history is generated. Never add private details to snapshots.

Preserve existing archived public `report.html` and `report.pdf` when replacing
a dated snapshot. Analysis does not generate or update these historical copies.
Site/report builds generate fresh reports and ignore archived copies. Preserve
only those report filenames, not arbitrary files from the old snapshot folder.

Only snapshot schema 7.0.0 is supported. Regenerate older documents from verified
dated sources; no legacy readers or fallback snapshots. `PublicSnapshot.load`
returns a string-keyed Hash. JSON Schema validates structure; Ruby validates
provenance and accounting. Analysis 3.7.0 changes output organisation, not the
2.1.0 methodology or analytical values.
Analysis 3.8.0 / methodology 2.2.0 trims Unicode whitespace and invisible format
characters at licence-value boundaries. Internal characters and multi-number
values remain unrecognised. Existing schema-7 snapshots retain their recorded
methodology; the metric accounting supports both 2.1.0 and 2.2.0.
Analysis 3.9.0 / methodology 2.3.0 also extracts one explicit number/AL token
from surrounding prose, requiring a single numeric sequence in the value.
Multiple numbers and partial tokens remain unrecognised. Schema-7 snapshots
from 2.1.0, 2.2.0 and 2.3.0 share metric accounting and keep their own versions.

`site:build` and `report:build[run_dir]` build public HTML/PDF using the complete
Jekyll page `site/report.html` and bundled wkhtmltopdf, without fallback.
Standalone outputs default to `tmp/reports/<run-id>/`, overridden by
`DESTINATION`, separate from the input. Builds leave inputs unchanged.
Analysis writes data only. Both public and private reports use the canonical
`site/report.html` Jekyll template and generate HTML/PDF. During
`bundle exec jekyll serve`, Jekyll sets `site.config["serving"]`; the report
generator reads the two diagnostic CSVs for each available source pair and adds
private report pages. Liquid shows links for those pairs. Private reports and
CSV downloads go into `_site/private-reports/<run-id>/` during local serving.
There is no custom HTTP handler, private ERB renderer or GitHub-specific flag.

Normal `jekyll build`, `site:build` and standalone `report:build` are public-only.
A normal build must remove private outputs left by local serving in the same
destination. Publication audits reject private files, report markers and links.
Private CSV inputs and snapshots remain unchanged by every build. Reanalysis
replaces diagnostics; restart Jekyll after updating inputs outside `site/`.

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

Raw data under `data_sources/**/*.csv`, detailed local results under `data/private/`, and cached files under `tmp/` are intentionally ignored by Git. Transformed, versioned outputs under `data/snapshots/` and `data/history/` are publishable project outputs and may be committed. Snapshot documents are aggregate-only and must not contain listing/host identifiers, listing URLs, names, addresses, exact coordinates, or raw licence strings. Do not commit large raw upstream datasets.

The GitHub Actions workflow in `.github/workflows/monthly-analysis.yml` runs monthly or through `workflow_dispatch`, tests before source updates and analysis, restores the latest retained `analysis-sources` artifact from a successful default-branch run, runs `sources:update`, archives only the latest dated pair with 90-day retention renewed each run, runs `analysis`, stages and audits only the sanitised `data/snapshots/` and `data/history/` outputs before committing them, builds the site from public snapshots, and publishes the site as a GitHub Pages artifact. Sources may be reused, but analysis always recalculates, even when the dated pair is unchanged. It must never commit local/detailed outputs or the generated site.

The `.github/workflows/site-publish.yml` workflow rebuilds and publishes the site on human pushes to `main` and through `workflow_dispatch`. It skips the automated `github-actions[bot]` / `Atualiza análise mensal` push because the monthly workflow already builds and publishes the site in that same run. Site publication is therefore separate from the data-analysis decision, while both use `bundle exec rake site:build` and the publication audit.

Rake is the interface for analysis, site builds and site checks; its tasks require `lib/alojamento_local.rb` inside the task and call `Analysis.run`, `SiteChecker` or the standard `jekyll build` CLI. The entry point configures Zeitwerk to load project constants from matching file paths. Keep standard-library and gem requires explicit; do not require individual project files. `public_schema.rb` defines shared constants and is explicitly required outside the loader. `test/alojamento_local_test.rb` checks eager loading for filename/constant consistency. npm provides frontend tooling through `npm run site:css`. Use `bundle exec rake -T` to list tasks. `bundle exec rake site:build` builds from existing public snapshots without running the analysis. `bundle exec rake site:check` checks the generated site. Test files load the application in the separate process launched by `Rake::TestTask`.

Before committing changes to `data/snapshots/`, `data/history/`, or publication workflows, run `ruby scripts/audit_publication.rb`. Run `ruby scripts/audit_publication.rb --history` when auditing repository history. A history rewrite requires a recoverable Git backup and coordinated approval before force-pushing.

The Airbnb snapshot is discovered from the public Inside Airbnb data page at runtime. `latest_airbnb_snapshot` must select the latest Lisbon `listings.csv.gz` entry and fail clearly if the page format changes. The run ID uses the date in the source filename, rather than assuming that the maximum listing-level `last_scraped` date is the archive date.

A fresh official register is downloaded with the actual current date in its filename only when needed for the Airbnb snapshot. Cached RNAL files retain their original download date. Analysis uses the latest dated local copy, never an undated file. The `metadata` section of `snapshot.json` records source URLs, source dates, SHA-256 hashes, Git commit, analysis version, methodology version, and output schema version.

Airbnb `last_scraped` values are listing-level collection dates and may span several days. They are not necessarily the same as the archive snapshot date.

Historical comparisons are generated only for metrics with the same methodology version. Comparisons across different methodology versions are marked incompatible. Reanalysis replaces the current public output for its dated source pair; previously committed results remain available through Git.

## Analysis architecture

`Analysis.run` is the orchestration entry point. It prepares sources, selects the destination, calculates results, and generates data inside the publication step. It returns `{run_id:, path:, private_path:, summary:}`. Supply both source paths or neither; omitting them selects the latest dated local pair. There is no separate `Runner` or facade for internal helpers.

- `Analysis::PreparedSources::Pair` owns source selection, preparation, dates, URLs, initial hashes, byte-change verification and the base source-date `identifier`.
- `Analysis::Classifier` produces detailed classified listing rows from that prepared pair. `Aggregates`, `AnnouncementCounts` and `RegistrationMetrics` calculate their respective aggregates without selecting or downloading sources.
- `Analysis::Result` takes `sources` and `run_id`; it owns classified listings, aggregates, summary and run metadata. Its `snapshot` builds and validates the current snapshot document as a Hash. The matched `official_register_date` is derived from classified listings here; the official download date belongs to source provenance.
- `Analysis::OutputWriter` is an instance holding a result and output path. Its generation methods own the snapshot document and separate private diagnostics; serialization helpers are private.
- `Analysis::History` owns comparisons and history CSV operations. `Analysis::PublicPublisher` stages and validates the snapshot, stages private diagnostics and histories, installs them together, rolls back failures or interruptions, and cleans staging files.

Use the responsible collaborator directly in scripts and focused tests rather than adding forwarding methods to `Analysis`. Keep the high-level sequence readable in `Analysis.run`, with setup details in private helpers. Structural refactors preserve the synthetic fixture's analytical results and output contents.

Public and private reports share the complete Jekyll page `site/report.html`, with
`layout: null`. `post_read` prepares `site.data.site`; the report generator loads
validated snapshots and creates pages before rendering. `post_write` copies
only aggregate downloads and generates PDFs. Rake invokes `jekyll build`, then
checks and audits output. Direct Jekyll builds also generate public PDFs.
`report:build` uses the same path with only report pages enabled. Presentation
defaults and bar widths belong in the page. `SiteChecker` verifies output files
and report/download links. Jekyll handles Liquid syntax; the publication audit
handles data/privacy validation. Report tests cover calculations, escaping,
historical defaults and equivalent rendering between standalone and site builds.
Builds write directly to the destination and may leave partial output on failure.
Snapshots and histories remain unchanged. Data publication uses
`Analysis::PublicPublisher` with validation and rollback, including diagnostics.
Older snapshots require verified reanalysis before building.

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
- To reproduce a prior run with a new methodology from verified local dated sources: `bundle exec rake 'analysis[<prior-public-run-id>]'`. Never relabel an old source as a fresh download.
- Circle areas and overlap use measured sets, including empty, disjoint, identical and contained sets. Announcement bubbles use a separate fractional scale.
- Regression metric tests in `test/registration_metrics_test.rb` and presentation geometry tests in `test/site_data_overlap_test.rb` also run through `test/versioned_analysis_test.rb`.

### Source preparation and methodology changes

- Prepare sources once per run with `Analysis::PreparedSources::Pair`; no cache by filename. Preserve every official entry and its raw fields. Derive the classification lookup separately so resolving official conflicts never changes the entries used by metrics.
- Retain Airbnb rows whose municipality normalizes to Lisboa. Derive reuse counts from those same retained entries; classification, spatial grouping and metrics must use the same population. Preserve original source values internally.
- Use the synthetic pipeline fixture for full aggregate/private output regression. Update its expected files only for an intentional change, review the diffs and independently check the accounting described in [test/fixtures/pipeline/README.md](test/fixtures/pipeline/README.md).
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
