# Extraction: WzJOIdUfMO4 (enriched)

## capabilities_mentioned
- Relief modeling (Aspire)
- multi-sheet job (walnut + maple inserts)
- shape creation: rounded (dome, flat-top limit), angular (preserve internal corners), smooth, custom, flat plane
- combine modes (add / merge)
- base height per component
- component tree (rename, level organization)
- scale Z height of model (exact height)
- pixel density / sheet sizing for detail
- model position in material

## workflow_steps
1. Open multi-sheet project (walnut plaque + maple insert) -> for detail, model on the SMALL sheet (pixel density) -> create rounded shape from vector (drag angle, flat-top limit handle) -> next components with combine mode = merge -> add base height for edge definition -> angular shapes for stars (preserve internal corners) -> rename components in component tree -> organize into levels (design/base) -> scale Z height of model to exact 0.25 -> build plaque on walnut sheet

## parameters_concepts
- modeling resolution (very high)
- shape angle/limit
- combine mode
- base height
- scale Z height (exact)
- sheet size vs pixel density
- model thickness vs material thickness

## gotchas_warnings
- Model on the smallest sheet that fits the model — pixel density = detail; big sheet wastes pixels
- Combine mode (add/merge) controls how shapes stack
- Base height gives the tool an edge to define at component borders
- Scale-Z-exact-height normalizes model thickness
- Levels enable swapping designs without touching toolpaths

## lean_relevance
**must**

## notes
Aspire-only relief modeling. Key concepts: combine modes, base height, pixel density, Z-scale. For ShopPilot's lean 3D, the takeaway is the component/heightfield model and model-in-material positioning — sculpt brushes are NOT required for lean.
