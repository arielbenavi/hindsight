# Fixtures: data-contract files for the MVP

One file per tester in the [data contract](../../docs/data-contract.md) format (v1). The iOS app bundles every `*.hindsight.json` here and lets you switch between them. **Frontend-owned** (Reut): these stand in for Ariel's pipeline until it outputs the same format, and then they get replaced.

| File | Source | Posts | Topics | Items |
|---|---|---|---|---|
| `reut.hindsight.json` | `data/ig-reut-export/` (Instagram export) | 324 | 16 | 239 |
| `ariel.hindsight.json` | `data/ig-saved-posts-seed.md` (Muse markdown; captions cut at 160 chars) | 1,216 | 22 | 445 |

## How they're made

```bash
cd data/fixtures
python3 tools/build_posts.py ig-export ../ig-reut-export work/reut.posts.json --handle reut_rabin
python3 tools/build_posts.py seed-md ../ig-saved-posts-seed.md work/ariel.posts.json --handle pudabeats
# per-post extraction: Claude subagents, following tools/EXTRACTION.md → extraction/<user>-NN.json
python3 tools/merge.py reut && python3 tools/merge.py ariel     # topics from tools/topics-<user>.json
python3 tools/validate.py *.hindsight.json
```

1. **`build_posts.py`**: deterministic `posts[]` (encoding fix, collections, hashtags, @mentions, `saved_at`).
2. **Extraction** (LLM, once): each post gets a lego screen, a topic hint and its `places` / `tip` / `routine`. The raw output is committed in `extraction/` so the merge can be re-run without redoing it.
3. **`merge.py`**: consolidates topic hints into named topics (`topics-<user>.json`, hand-written), applies the "< 5 fitness posts → Learn" rule, picks samples, writes the file.
4. **`validate.py`**: checks the contract rules (enums, no `""`, each post in one topic, one item per non-`none` post, lengths). Warnings are fine; errors aren't.

`<user>.matches.json` is a warm Apple Maps cache (same shape as the app's `match-cache.json`), copied from a simulator run so testers' first launch doesn't need hundreds of live MapKit searches. Refresh it by running the app on that dataset and copying `Library/Application Support/Hindsight/<user>/match-cache.json`.

`work/` is scratch and not committed. Adding a tester: build their posts, run extraction on the batches, write `topics-<name>.json`, merge, validate.
