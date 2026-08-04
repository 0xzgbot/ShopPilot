# Extraction: Txafg3oN8c0 (enriched)

## capabilities_mentioned
- save toolpaths (final step)
- machine + post processor selection
- post processor = XY/Z -> controller format
- default post per machine
- save selected / visible-to-one-file / multiple files / group-where-possible
- tool-change support (ATC) constraint
- tap file output
- file dialog default location (global/operation/job)
- preview before save

## workflow_steps
1. Preview all toolpaths first -> save toolpath icon -> choose machine + post processor (post converts coords to controller dialect) -> configure machine if prompted (or default to last-used post) -> choose save mode: selected / visible-to-one-file / multiple files / group where possible -> save -> know the output folder (take file to machine via USB)

## parameters_concepts
- post processor (g-code inches etc.)
- default post per machine
- file output format (.tap for controller)
- save modes: one-file vs multi-file vs group-by-tool

## gotchas_warnings
- Post processor choice depends on controller software — check manufacturer if unsure
- Visible-to-one-file FAILS if toolpaths use different tools and post has no tool-change (ATC) support
- Multiple-files save respects toolpath order (1,2,3... = cut order)
- Group-where-possible packs by tool to cut tool changes
- Default post per machine speeds repeat saves

## lean_relevance
**must**

## notes
The output contract: post processor is the dialect translator; grouping rules respect tool changes. Directly informs ShopPilot's GRBL post + multi-file save design.
