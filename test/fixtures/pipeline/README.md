# Synthetic regression fixtures

`sources/` contains invented source CSVs. Tests copy them to a temporary directory
before registering manifests or analysing, so source fixtures remain unchanged.
`expected/` is the reviewed source-to-snapshot baseline, independent of the
presentation fixture. There are no legacy expectations or history files.

## Source accounting

The Airbnb fixture has 12 source rows: IDs 1–11 declare Lisboa, ID 12 declares
Porto and is excluded. Thus there are **11 original listings**: ten in Arroios and
one with unknown Airbnb parish (ID 11).

- IDs 1 and 2 declare number 100 and merge. They are room listings with different
  bedroom counts; this does not establish separate apartments. Their medoid tie
  selects ID 1, at the official location.
- ID 3 declares 100 at a separate location.
- ID 4 declares 100 and 200 plus unsupported residual text. It creates two
  contributions, no residual unnumbered contribution, and stays separate.
- IDs 5 and 6 declare `Exempt`. They remain separate unnumbered candidates even
  though the other source evidence agrees.
- ID 7 has no declaration; ID 8 declares an unsupported UT registration.
- ID 9 declares 300 with missing listing coordinates.
- ID 10 declares 200 near ID 4. Its score is 6: review, kept separate.
- ID 11 declares 400 with unknown Airbnb parish.

There are **12 contributions**, **11 candidates** (7 numbered and 4 unnumbered),
and **4 distinct AL numbers**. Every retained ID appears; ID 4 appears in two
numbers. Assessment pairs: six for 100 and one for 200, including one merge and
one review. IDs, groups and medoids are invariant under source-row reversal.

The national RNAL fixture has six rows and four numbers:

- 100 has two equivalent normalized numbers and identical coordinate pairs,
  with conflicting official parishes Arroios/Belém. Municipality and coordinates
  resolve, parish stays null.
- 200 appears in Lisboa/Belém and Porto/Bonfim with conflicting locations and
  regions. Municipality, dependent parish/location and region stay null. It is
  still `found` nationally.
- 300 appears in Lisboa/Arroios without coordinates.
- 400 appears in Faro/Sé without region.

The independent Lisbon RNAL summary has **3 distinct numbers**. Arroios has
100/300 (2) and Belém has 100/200 (2), so local distinct counts sum to 4 rather
than the city total 3. Unknown official parish has zero. No source row is dropped
when resolving national conflicts.

`expected/public/snapshot.json` is the full canonical candidate document.
It is the sole analysis output; no private directory or diagnostic files are generated.
Source manifests remain beside the copied CSV inputs.
Review diffs and independently recount these relationships before updating.

## Presentation fixture

`snapshots/candidate/snapshot.json` is a separate invented dataset for the
established site/report UX. It has **13 original listings**, **12 candidates**,
**7 distinct candidate numbers** and **17 distinct RNAL numbers**. It includes a
three-listing merged candidate, a listing contributing to two numbers, unknown
geography, repeated numbers, a national nonmatch and two singleton exemptions.
It now includes original declarations and complete pair assessments without
changing those established presentation counts. Demo IDs never get live links.
Select it explicitly using `SNAPSHOT=test/fixtures/pipeline/snapshots/candidate`.
It is not the output generated from `sources/`.
