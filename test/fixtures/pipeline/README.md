# Synthetic pipeline regression fixture

All rows are invented. The licence numbers, hosts, names, addresses and
`example.invalid` URLs are test values, not downloaded or anonymized records.
The fixture uses known Lisbon geography names to exercise the existing rules.

`PipelineRegressionTest` runs the single analysis from dated synthetic CSVs,
seeds the aggregate history with compatible and incompatible runs. It compares
6 result files: one public snapshot, two private diagnostic CSVs and three
aggregate histories. The v2 site no longer consumes these outputs; its independent
candidate snapshot inputs live in `snapshots/candidate/` and are covered by
`CandidateDatasetTest` and `ReportBuildTest`. The 3.7.0/schema 7.0.0 baseline removes
mode fields, the duplicate local snapshot and private history. Analytical
accounting, methodology, CSV rows and aggregate histories remain unchanged.
Only schema 7.0.0 is supported; previous formats require verified reanalysis.

The 3.8.0 / methodology 2.2.0 parser trims invisible Unicode characters at
licence-value boundaries. These synthetic sources contain no such values, so
their analytical outputs remain unchanged. Expected version fields and the
synthetic comparable-history row move to 2.2.0; no counts are adjusted.

The current 3.9.0 / methodology 2.3.0 baseline adds extraction of one explicit
number/AL token from surrounding prose. No synthetic source row changes its
parsed number; expected versions and the comparable-history row move to 2.3.0
with identical counts and detailed outputs.

The test does not download sources, use repository snapshots or private caches,
invoke Jekyll, or create a PDF. Site builds and publication audits remain separate
CI checks. A dedicated regression test also audits the synthetic public artifact.
The empty fixture-owned quotes file keeps editorial changes out of this test.

## Cases

| Number / source row | Purpose |
| --- | --- |
| `001` / `1` | Two identical official entries; normalized leading zeroes; room establishment observed in two parishes with different hosts |
| `2` | Repetition in one location without room/unit terms |
| `3` | Same host across several locations; a connected chain plus a distant cluster; distance history over 5 km |
| `4`, `5` | Officially outside Lisbon; known versus missing region; outside classification takes priority over missing observed coordinates |
| `6` | Identifiable number absent nationally; nearby announcements remain separate |
| `7`, `15` | Missing/sentinel official municipality |
| `8`, `9`, `10`, `20` | Conflicting municipalities, parishes, coordinates, and known/missing municipalities |
| `11` | Anchored `Registration Number:` prefix; exact coordinate match; listing scrape date differs from archive date |
| `12` | One missing-coordinate announcement prevents the group from collapsing |
| `13`, `22` | RNAL-only numbers; the observed Porto row for `22` is excluded |
| `406/UT/2017` | Unparseable official number retained in official-entry counts |
| `16`, `18` | Unknown official parish and unknown observed parish |
| `17` | Legacy year format; officially registered in another Lisbon parish |
| `21` | Chain endpoints exceed 500 m but form one connected component |
| Empty, whitespace, `Exempt`, `/UT/` | Disjoint empty and filled-unrecognized announcement counts |
| ` Lisboa `, `lisboa`, `Porto` | Normalized Lisbon variants enter classification, metrics and reuse counts; Porto is excluded |

## Independent accounting

There are 25 official rows. Nineteen declare Lisbon, of which one has no
parseable AL number; those rows produce 15 distinct Lisbon numbers. Five extra
entries repeat numbers, three entries have unresolved municipalities, and two
Lisbon entries have unknown parishes.

The source has 36 announcements. Two Porto rows are excluded. The 34 included
announcements contain 30 identifiable
numbers, two empty licences and two filled-unrecognized licences. Two
identifiable announcements use `6`, absent from RNAL, so 28 match nationally.

Lisbon RNAL numbers are `1,2,3,8,9,10,11,12,13,16,17,18,20,21,22`.
Observed numbers are `1,2,3,4,5,6,7,8,9,10,11,12,15,16,17,18,20,21`.
Their intersection has 13 numbers. RNAL-only is `13,22`; Airbnb-only is
`4,5` (other municipality), `6` (no national match), and `7,15` (unresolved).

The estimate collapses three announcements for `1`, one for `2`, and two for `21`:
`34 - 3 - 1 - 2 = 28`. It leaves all suspicious, unmatched, outside and unresolved
cases separate. The independent test pins these totals, all difference
categories, every geography, diagnostics, classifications and source dates.

## Updating expectations

Normal tests only read `expected/`; they never regenerate it. To update it after
an intentional, reviewed behavior change:

```bash
ruby test/support/update_pipeline_expectations.rb --write
bundle exec rake test TEST=test/pipeline_regression_test.rb
```

Review every changed expected file and the independent accounting assertions.
Do not update the baseline merely to make a failing refactor pass. Version fields,
source hashes, dates, definitions, row ordering and unknown/new fields are retained.
Only these volatile values are replaced with explicit placeholders:

- Top-level `generated_at` in current summaries, including the site summary
  and the consolidated document summary.
- The current run's `generated_at` column in summary histories; seed dates remain.
- `git_commit` and `git_worktree_dirty` in metadata, including site metadata
  and snapshot metadata.

If files are intentionally removed, delete their obsolete expectations explicitly;
the updater does not delete files and the test rejects unexpected/missing outputs.

## Candidate snapshot used by the v2 site

`snapshots/candidate/snapshot.json` is an invented cleaned output,
not generated by the old CSV analysis fixture. They exercise the new presentation
contract and are shared by candidate/report tests and the temporary Jekyll
`snapshot` configuration. There is no synthetic marker or special test schema.
`schema/candidate_snapshot.schema.json` describes the shared structure; Ruby
validates accounting across records.
Future real snapshots use the same file under `data/snapshots/candidate/`.

Independent counts: 12 candidates, 13 distinct listing IDs, 7 distinct AL numbers;
RNAL has one count of 17 distinct AL numbers. Original listing summaries are
independent of candidate assignments: Arroios has 8 source listings, 5 candidates
and 4 declared numbers; Estrela has 0 source listings and 1 assigned candidate.
The original per-parish counts, including unknown geography, sum to 13. `demo-105` contributes to two numbered candidates; three room
listings contribute to candidate-002. Two candidates share 100005 in separate
locations, at 0.2 km and 6.2 km from their RNAL match. The distance distribution counts
that number once in «Mais de 5 km», while its headline counts 2 distinct listings. demo-107 is reported in Arroios but its candidate is assigned to
Estrela from coordinates. One candidate has unknown parish; one in Arroios has a Faro
RNAL match in NUTS II Algarve; the outside-Lisbon region distribution counts
that listing once. Lisbon matches use Grande Lisboa. The unidentified-licence signal counts 2 distinct listings: demo-112
has an empty field and demo-111 an unrecognised value. Declared exemptions
(demo-109 and demo-110) use registration_status `exempt` and are excluded from this signal.
Each candidate has a single `official_match` object when found, otherwise null.
The candidate-to-RNAL distance lives inside that object as `distance_km`: 217 km
for the Faro match, 0.2 and 6.2 km for the repeated number, null when unmeasured.
Reuse counts are derived from candidates; the chart takes the largest RNAL distance
for each repeated number. There is no `reuse` object. Geography contains only coordinate-derived and
Airbnb-reported parishes; assignment reasons and boundary flags are deferred.
Correspondence and exemption assessment fields are deferred.
Capacity is intentionally absent. No test IDs link to real listings.

The candidate fixture has invented source dates: RNAL fetched 2024-07-01,
Airbnb fetched 2024-06-03, Airbnb archive dated 2024-06-01. These dates deliberately
differ to exercise provenance rendering; they are not actual downloads or file mtimes.
