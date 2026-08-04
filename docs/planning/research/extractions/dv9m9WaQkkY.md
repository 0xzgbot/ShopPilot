# Extraction: dv9m9WaQkkY (enriched)

## capabilities_mentioned
- Bitmap trace (bitmap → closed vectors)
- Black-and-white vs color trace modes
- Vector grouping of traced output
- Layer management (color, rename, delete bitmap layer)

## workflow_steps
1. Import bitmap (PNG etc.) into job.
2. Bitmap trace tool: choose trace type (black-and-white for B&W images; color mode for multi-color) → set number of colors → preview → group traced vectors.
3. Delete the original bitmap + its layer; keep traced vectors.
4. (Follow-up) V-Carve the traced vectors.

## parameters_concepts
- trace type (B&W vs color)
- number of colors
- grouping of output vectors

## gotchas_warnings
- Traced output must be CLOSED vectors for V-carving — group them so they stay manageable
- Bitmap can't be V-carved directly; trace first
- Traced vectors often need cleanup (validator pass) before toolpathing

## lean_relevance
**should**

## notes
Bitmap trace is the bridge from logos/artwork to V-carve. It's a Wave-2 defer but valuable for sign work — the core need is B&W outline→closed vectors with grouping; color trace is a luxury. Validator integration matters here more than the trace itself (traces produce open/duplicate vectors).
