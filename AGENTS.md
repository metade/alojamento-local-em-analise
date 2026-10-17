# Agent and contributor guide

## Purpose and scope

Compare Lisbon Airbnb listings with the national Portuguese local-accommodation
register. Results are investigative indicators for verification, never legal
findings that a listing or establishment is illegal.

Use **listing** and **candidate** in code/data; public Portuguese copy uses
**anúncio** and **candidato**. Preserve the existing homepage, parish pages,
quotes, signal cards, overlap component, map and report styling. Change data
bindings and necessary terminology, not the UX. Do not restore the removed yellow
bubble. The user handles screenshots for now: use tests/builds without captures.
Do not download sources, deploy or change `research/` during local implementation
unless explicitly requested.

## Current candidate pipeline

`Analysis.run` is the orchestration entry point. Supply both `airbnb_path` and
`official_path` or neither; omission selects the latest dated local CSV pair
without network requests. It returns `{run_id:, path:, summary:}`.
There is no `analysis[run_id]`, parallel pipeline, legacy snapshot reader, output
version infrastructure or historical comparison subsystem.

The sole analysis output is `data/snapshots/<airbnb-archive-date>__<rnal-source-file-date>/snapshot.json`.
Do not generate diagnostics or private outputs. Source manifests stay beside CSVs.
Folder dates identify
selected files; they do not prove download dates. Reanalysis safely replaces that
pair. Other pairs are unchanged. Old outputs are retained only in Git history.

Collaborators:

- `Analysis::Data`: downloads, dated local discovery, manifests, artifact staging.
- `DataSource`: one preparation per run, initial hashes, manifests and
  source-change checks. `Airbnb` retains Lisbon rows; `Official` keeps all source
  entries and independently resolves national records.
- `Declaration`: conservative normalization, multiple explicit AL tokens, raw text
  and residual retention, whole-value exemptions.
- `Grouping`: scored pairs, deterministic complete-link groups and medoids.
- `Boundaries`: full-resolution CML polygon lookup.
- `DatasetBuilder`: builds a validated `CandidateDataset` from prepared sources,
  with candidates, independent original-listing/RNAL summaries and source assertions.
- `CandidateDataset`: the shared result object for generated and loaded documents;
  owns document validation, accessors and the analysis summary.
- `ResultPublisher`: stage, validate, reread, recheck sources,
  atomically rename snapshot as final commit; lock the destination directory.

Preserve Zeitwerk conventions. Require gems/standard libraries explicitly; do not
require individual project files. Use responsible collaborators directly in
focused scripts/tests, without facade forwarding methods. `lib/alojamento_local.rb`
sets up the loader and shared licence/coordinate helpers.

## Contract and accounting

`CandidateDataset` and `schema/candidate_snapshot.schema.json` define the sole
public contract. JSON Schema validates structure; Ruby validates relationships.
The document has `source_dates`, `rnal`, `listings`, `candidates` and
`grouping_assessments`. No synthetic flags or test/production formats.

`airbnb_snapshot_date` is required and drives “Anúncios de”. Fetch dates
`airbnb_fetched_on` and `rnal_fetched_on` may be null. Never infer them from mtime,
listing `last_scraped`, backups or today. Local `*.csv.manifest.json` files record
URLs, filenames, SHA-256, archive/source dates and documented fetch dates. Future
successful downloads record the actual fetch date. Cache reuse and source
artifacts preserve manifests. `sources:register` registers dated cached files
offline with unknown fetch dates null.

Each candidate has zero or one normalized AL number and references one or more
listing IDs. Each listing–number contribution appears exactly once and all
distinct referenced IDs equal the original listing population. Each candidate
has one parish or unknown, so totals are additive. Original listing totals are
computed independently before expansion/grouping, overall and by Airbnb source
parish, including unknown. Never derive them from candidates or candidate geography.
RNAL counts distinct numbers on source rows declaring Lisboa, overall and per
official parish including unknown; distinct parish counts need not be additive.

`raw_licences` maps each contributing ID to the unchanged original licence text
or null. Publication of raw licence values is an explicitly authorized exception.
Other public fields continue to exclude host IDs, descriptions, names, addresses
and exact listing coordinates. Escape all strings when rendered. Numeric listing
IDs get live listing links; `demo-` IDs do not.

Full original declarations stay in `raw_licences`. Partial extraction receives a
signal but does not create an additional unnumbered contribution. Exemptions
require whole-value declarations. `Exempt` is never an AL number, never enters
number reuse and never groups listings. All unnumbered contributions remain
singleton candidates, including exemptions. Track future investigation in TODO.md.

Pair assessments cover only the same non-null AL number, uniquely, and agree
with final groups. Scores summarize evidence, not probabilities. Use the rules
and thresholds documented in README; every pair in a merged group must qualify.
Choose eligible unions by highest minimum cross-pair score, then sorted listing
IDs. Qualifying pairs left apart by conflicts become review. RNAL never affects
grouping. Different hosts do not automatically block merging; bedroom differences
only contradict two entire-apartment listings, not room listings.

Use member medoids for coordinate parish and RNAL distances, breaking ties by
listing ID. Assign candidate parish only when all members report the same
recognized Airbnb parish; keep unknown otherwise. Airbnb geography is unverified.
Keep coordinate, Airbnb and official parishes separately. Never override assignment
with coordinates yet. `data/freguesia_boundaries.json` is the minimal full-resolution
analytical derivative, with attribution/original hash. The supplied original is committed at
`data_sources/lisboa-freguesias.geojson`, the sole boundary-source exception to
the source-file publication audit. Do not use simplified display paths for analysis.

National RNAL records resolve nonmissing normalized values by consensus. Conflicts
become null. Resolve coordinates as pairs. Municipality
conflicts also leave dependent parish/location unresolved. Never choose the first
row or the nearest record. `found` means national existence, even with unresolved
fields. `official_match` is an object only for `found`; its `distance_km` is from
the medoid to resolved RNAL coordinates. `NUTSII` maps to `district`. There is no
reuse object or placeholder correspondence/exemption/capacity assessment.

## Site and report semantics

Default selection is the latest dated snapshot directory; validate it and fail
without falling back. `SNAPSHOT` overrides selection explicitly. The invented
presentation fixture remains `test/fixtures/pipeline/snapshots/candidate`.
Publish the selected dataset at `/snapshots/<folder>/snapshot.json`; derive every
download path from it. Public `report.html` and `report.pdf` stay at the site root.
There is one report, shared by public builds and local serving; do not add a
private report generator, template or route. Both site and standalone report
builds use canonical `site/report.html`, with
`layout: null`. PDF is a derivative generated through bundled wkhtmltopdf, without
fallback. Builds never alter source snapshots and may leave partial destination
output on failure. Successful builds remove stale legacy/private outputs.

A tabela detalhada dos relatórios omite candidatos sem sinais nem revisão de
agrupamento, com número encontrado no RNAL em Lisboa, freguesias atribuída, por
coordenadas e oficial concordantes e distância conhecida até 500 m. Casos por
resolver permanecem visíveis. Totais, gráficos e downloads incluem todos os
candidatos; a omissão não é uma certificação legal.

The overlap diagram counts all candidates as Airbnb; numbered candidates form
the intersection and unnumbered candidates the Airbnb-only area. Count repeated
numbers once per candidate regardless of RNAL lookup. If numbered candidates
exceed RNAL, retain counts without impossible proportional geometry. Unknown
measures show `???` and create no measured areas.

The unidentified-licence signal counts distinct listing IDs with absent or
unrecognised values, excluding declared exemptions. Reuse groups non-null numbers
across candidates. Its headline counts distinct listings; its chart counts each
number once using the largest `official_match.distance_km`, with any missing
match/distance explicitly unresolved. Regional charts count distinct IDs for
resolved non-Lisbon municipalities; missing/contradictory NUTS II remain unresolved.

Preserve methodology anchors. The district locator uses simplified CML boundaries
in `site/_data/freguesia_map.json`, showing only administrative outlines.

## Commands and verification

```bash
bundle exec rake sources:register
bundle exec rake analysis
DESTINATION=tmp/candidate-site bundle exec rake site:build site:check
DESTINATION=tmp/candidate-report bundle exec rake 'report:build[data/snapshots/2026-06-23__2026-09-26]'
bundle exec rake test
npm run site:format
npm run site:lint
ruby scripts/audit_publication.rb
```

`site:build` consumes existing output without analysis. `report:build[input-dir]`
uses the same report template. `rebuild` analyses local sources then builds;
`refresh` updates sources first. `sources:update` uses the network only when
explicitly requested; `FORCE=1` applies only there. `sources:archive` stages just
the selected CSV pair and manifests. Use `bundle exec rake -T` for tasks.

Add meaningful regression tests for parsing, spatial/grouping rules, source
conflicts and publication failure paths. Synthetic sources and reviewed expected
outputs live under `test/fixtures/pipeline/`; read its README before changes.
The separate presentation fixture preserves its established counts. Do not use
real datasets in tests. Test full ID coverage of the real run independently.

Format only source HTML/Liquid with Prettier (two spaces, preferred width 100),
not generated pages or historical output. Use tests/builds without screenshots.
Before committing snapshots or workflows, run `ruby scripts/audit_publication.rb`.
The optional `--history` safety audit does not add compatibility readers. Rewriting
history requires recoverable backup and coordinated approval.

## CI and privacy

Monthly CI tests first, restores retained sources, updates explicitly, stages the
selected pair plus manifests with renewed 90-day retention, analyses, stages only
the generated dated snapshot, audits, builds and inspects `_site/report.pdf`.
Site-only CI builds on human main pushes/manual runs; it skips the monthly bot
push. Both publish a separate audited Pages artifact. Never commit raw sources,
generated sites. Airbnb/RNAL CSV sources, manifests, legacy `data/private/`
and `tmp/` are ignored. Work left for later belongs in [TODO.md](TODO.md).
