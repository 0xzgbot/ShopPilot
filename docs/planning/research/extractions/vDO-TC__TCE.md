# Extraction: vDO-TC__TCE (enriched)

## capabilities_mentioned
- vector validator (find overlaps/intersections/zero-length spans)
- edit selection: select all duplicate vectors / open vectors
- join vectors with tolerance
- node editing (n key)
- V-Carve mode validation (ignores font intersections)
- fix zero-length spans (auto)

## workflow_steps
1. Select vectors -> vector validator -> search selected -> review overlaps/intersections/zero-length spans -> select-all-duplicate-vectors to find dupes -> delete -> join open vectors (low tolerance, N open -> 1 closed) -> re-validate -> for V-Carve intent, check V-Carve mode (ignores text font intersections) -> fix zero-length spans automatically

## parameters_concepts
- join tolerance
- overlap/intersection/zero-span counts
- V-Carve mode

## gotchas_warnings
- Looks-fine vectors can hide duplicate/overlapping contours that break toolpaths
- Open vectors: 4 individual vectors look like 1 closed shape to the eye — profile toolpath won't loop
- V-Carve mode ignores text intersections (font artifacts) — different validation rules per toolpath type
- Zero-length spans: duplicate nodes; auto-fixable
- Always validate imported data before toolpathing

## lean_relevance
**must**

## notes
Preflight tool for imports. Duplicates, open vectors, intersections, zero-length spans — all things that silently break toolpath generation. Directly supports ShopPilot's vector-validator / preflight plan.
