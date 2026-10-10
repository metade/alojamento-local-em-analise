# Agent and contributor guide

## Project purpose

This project compares Airbnb listing snapshots for Lisbon with the official Portuguese local-accommodation register. It identifies licence matches, formatting mismatches, possible repeated use of licence numbers, and listings whose apparent location differs from the official record.

The analysis is investigative. A result is an indicator for verification, not a legal finding that a listing or establishment is illegal.

## Running the project

Install dependencies:

```bash
bundle install
```

Run the analysis:

```bash
bundle exec ruby run_me.rb
```

The default mode is `local`. It downloads missing public source snapshots and creates an immutable detailed run under:

```text
data/private/<airbnb-snapshot-date>__<official-download-date>/
```

Local runs are immutable. For development reruns, `bundle exec ruby run_me.rb --force` preserves the existing run and writes a timestamped sibling rerun; `--force` is not supported for public runs.

Use the explicit public mode to create sanitised, publishable outputs:

```bash
bundle exec ruby run_me.rb --mode public
```

Public runs are created under:

```text
data/snapshots/<airbnb-snapshot-date>__<official-download-date>/
```

The public mode preserves run immutability. Automated workflows may use `bundle exec ruby run_me.rb --mode public --reuse-existing`: when the calculated public run ID already exists, the existing snapshot is reused without being rewritten so publication can continue.

Local runs use distinct names such as `listings_detailed.csv`, `licence_groups_detailed.csv`, `metadata_local.json`, `summary_local.json`, and `report_local.html`; they may contain diagnostic fields and are ignored by Git. Public runs contain `metadata.json`, `summary.json`, `listings.csv`, `licence_groups.csv`, `freguesias.csv`, and `report.html`. Set `GENERATE_PDF=1` to create the optional PDF derivative when `wkhtmltopdf` or `weasyprint` is installed. Historical summary rows are appended to `data/history/summary.csv` for public runs and `data/private/history/summary.csv` for local runs; an existing run ID must never be overwritten.

Run tests:

```bash
ruby -Itest test/al_ilegal_test.rb
ruby -Itest test/spatial_clusters_test.rb
ruby -Itest test/versioned_analysis_test.rb
```

Ruby syntax checks:

```bash
ruby -c run_me.rb
ruby -c lib/al_ilegal.rb
ruby -c lib/al_ilegal/data.rb
```

## Data and reproducibility

Raw data under `data_sources/**/*.csv`, detailed local results under `data/private/`, and cached files under `tmp/` are intentionally ignored by Git. Transformed, versioned outputs under `data/snapshots/` and `data/history/` are publishable project outputs and may be committed. Snapshot CSVs are aggregate-only and must not contain listing/host identifiers, listing URLs, names, addresses, exact coordinates, or raw licence strings. Do not commit large raw upstream datasets.

The GitHub Actions workflow in `.github/workflows/quarterly-analysis.yml` runs quarterly or through `workflow_dispatch`, tests before analysis, explicitly selects `--mode public --reuse-existing`, stages and audits only the sanitised `data/snapshots/` and `data/history/` outputs before committing them, builds the site from public snapshots, and publishes the site as a GitHub Pages artifact. Reusing an existing run is not a data rerun and never overwrites an immutable snapshot. It must never commit local/detailed outputs or the generated site.

The `.github/workflows/site-publish.yml` workflow rebuilds and publishes the site on human pushes to `main` and through `workflow_dispatch`. It skips the automated `github-actions[bot]` / `Atualiza análise trimestral` push because the quarterly workflow already builds and publishes the site in that same run. Site publication is therefore separate from the data-analysis decision, while both use `scripts/build_site.rb` and the publication audit.

Before committing changes to `data/snapshots/`, `data/history/`, or publication workflows, run `ruby scripts/audit_publication.rb`. Run `ruby scripts/audit_publication.rb --history` when auditing repository history. A history rewrite requires a recoverable Git backup and coordinated approval before force-pushing.

The Airbnb snapshot is discovered from the public Inside Airbnb data page at runtime. `latest_airbnb_snapshot` must select the latest Lisbon `listings.csv.gz` entry and fail clearly if the page format changes. The run ID uses the date in the source filename, rather than assuming that the maximum listing-level `last_scraped` date is the archive date.

The official register is downloaded with the current date in its filename. The analysis uses the dated file returned by the downloader, not an older undated copy. `metadata.json` records source URLs, source dates, SHA-256 hashes, Git commit, analysis version, methodology version, and output schema version.

Airbnb `last_scraped` values are listing-level collection dates and may span several days. They are not necessarily the same as the archive snapshot date.

Historical comparisons are generated only for metrics with the same methodology version. When the methodology changes, old outputs remain untouched and comparisons are marked incompatible.

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

### Statistics to complete after the UX treatment

The homepage overlap diagram, `site/_includes/district-overlap.html`, and the RNAL metric in `site/_layouts/district.html` contain deliberate UX example counts. District examples are identical across freguesias and are not measured results. Keep the example labels visible until reproducible aggregate statistics replace them. The current scope is UX only; do not replace the examples with ad hoc calculations. Replace the district RNAL headline and overlap set total together so they remain consistent.

- Calculate distinct normalized AL registration numbers for Lisbon and each freguesia: the RNAL set uses official `Concelho` and `Freguesia`; the Airbnb set uses the observed announcement's freguesia. Publish both set totals, their intersection, and both differences.
- Break down Airbnb numbers outside the local RNAL set into registrations in another Lisbon freguesia, another municipality, and numbers with no RNAL match. “Only Airbnb in this freguesia” must not imply absence from the national register. RNAL-only means absent from the Airbnb set for that freguesia, not necessarily absent from Airbnb elsewhere.
- Count announcements with no identifiable AL number separately (empty field and unrecognised value). These are announcement counts, not a third set of distinct registration numbers. Existing `identifiable_licences` fields also count announcements, not unique licences or confirmed RNAL matches.
- Use the exact dated sources and SHA-256 hashes of the selected run, normalize parish names consistently, and account explicitly for missing/unknown official freguesias. A registration may appear in Airbnb sets for several freguesias; do not sum parish distinct-number counts as a city total.
- Add versioned, aggregate-only outputs and regression tests before wiring real values into the diagrams. Preserve existing snapshot immutability, record the metric definitions and versions, and audit publication. Scale circle areas and overlap to the real set counts, including zero, disjoint, and contained sets.

### General guidance

- Follow the homepage and freguesia pages for site UX: Tailwind utilities, existing design tokens, concise Portuguese copy, and qualified estimates. Keep the grouping explanation with the Airbnb figures; RNAL registrations are a separate source, not the input to that estimate.
- The district locator uses CML administrative boundaries from `site/_data/freguesia_map.json`. It highlights the selected freguesia within Lisbon; it does not show announcement locations or density.
- Preserve methodology anchors linked from other pages when simplifying `site/metodologia.html`.
- Preserve `licensa_raw` in internal analysis rows when changing licence parsing so the source value remains auditable; never write it to public outputs.
- Add regression tests for new licence formats and spatial rules.
- Do not describe unmatched or geographically inconsistent listings as illegal without official validation.
- Do not commit raw downloaded datasets unless explicitly requested.
- Treat `report.html` as the canonical self-contained report and `report.pdf` as a derivative.
- Do not recreate or maintain the removed legacy `relatorio_anomalias_al.*` files; new reports belong inside their versioned run directory.
- For homepage layout changes, run `npm run site:screenshots`. For other page layouts, build with `npm run site:build`, then run `node scripts/capture_homepage.mjs <page-path>` (for example, `freguesias/arroios/index.html` or `metodologia.html`). Inspect the 1440, 768, and 390 px images in `tmp/screenshots/`; the script checks for horizontal overflow.
