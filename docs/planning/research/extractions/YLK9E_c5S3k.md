# Extraction: YLK9E_c5S3k (enriched)

## capabilities_mentioned
- Project size/position setup
- model vs material size distinction
- linked width/height scaling
- material thickness check with warning
- model position in material (top/bottom/middle)
- XY origin selection (datum)
- Z origin (material surface vs spoilboard)
- job offset from origin
- thickness warning validation

## workflow_steps
1. Set units (in/mm) -> set model size (w/h linked, depth optional) -> set material properties (material type, thickness) -> resolve thickness-vs-depth warning -> choose model position in material (top/bottom/middle, gap above) -> set XY origin (lower-left/center/etc) -> set Z origin (material surface/spoilboard) -> optional offset from origin -> validate material big enough + hold-down plan

## parameters_concepts
- model size vs material size
- material thickness
- model depth
- gap above/below model
- XY origin
- Z origin
- job offset

## gotchas_warnings
- Software warns when model depth > material thickness — must fix before toolpathing
- Model size is NOT material size — two separate concepts
- XY/Z origin settings MUST match where you zero on the machine
- Material must be large enough + consider hold-down and tool over-travel past origin

## lean_relevance
**must**

## notes
Preflight discipline video: model-vs-material size separation, origin matching, and the thickness warning. Confirms the 'warn, don't block' pattern for setup validation.
