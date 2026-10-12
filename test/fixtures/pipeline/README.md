# Synthetic pipeline regression fixture

All rows are invented. The licence numbers, hosts, names, addresses and
`example.invalid` URLs are test values, not downloaded or anonymized records.
The fixture uses known Lisbon geography names to exercise the existing rules.

`PipelineRegressionTest` runs public and local analysis from the dated source
CSVs, seeds each history with compatible and incompatible runs, and feeds the
public result and its auxiliary histories into `SiteData`. It compares all 19
result files against `expected/`, including CSV headers/order, detailed rows,
metadata, every registration metric/definition/diagnostic, reports, histories,
and all district data/routes/geometry.

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

- Top-level `generated_at` in current summaries, including the site summary.
- The current run's `generated_at` column in summary histories; seed dates remain.
- The report header's generation timestamp.
- `git_commit` and `git_worktree_dirty` in metadata, including site metadata.

If files are intentionally removed, delete their obsolete expectations explicitly;
the updater does not delete files and the test rejects unexpected/missing outputs.
