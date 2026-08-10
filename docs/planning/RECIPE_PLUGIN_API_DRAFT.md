# ShopPilot Recipe & Plugin API — Draft (SPK-1006)

> Status: **Draft** — the JSON recipe format is implemented (see below); the
> plugin API is a design proposal for v2.0, not yet a loadable ABI.

## 1. JSON Recipe Format (implemented)

A recipe is a single JSON object describing a job template. Files live in
`fixtures/recipes/*.recipe.json`; the format is Codable via `JobRecipe`
(`Sources/ShopPilotCore/JobRecipe.swift`).

### Schema

```json
{
  "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
  "name": "Portrait Relief",
  "description": "Portrait-style relief carving with fine detail in the face area.",
  "icon": "person.crop.circle",
  "stockWidth": 304.8,
  "stockDepth": 457.2,
  "stockHeight": 19.05,
  "recommendedStrategy": "Adaptive Z-level roughing + parallel finishing"
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `id` | UUID string | Stable recipe identity (merge key) |
| `name` | string | Display name in the New Job picker |
| `description` | string | One-line purpose |
| `icon` | string | SF Symbol name for the picker row |
| `stockWidth` / `stockDepth` / `stockHeight` | number (mm) | Default stock dimensions |
| `recommendedStrategy` | string | The suggested toolpath strategy |

### Codec contract (`RecipeJSONCodec`)

- `encode(_:)` — pretty-printed, sorted keys.
- `decode(_:)` — single recipe; unknown keys tolerated (forward-compatible).
- `decodePack(_:)` — JSON array of recipes.
- `decodeEnvelope(_:)` — `{"recipes": [...]}` envelope OR bare array (the
  plugin/API shape).

## 2. Sample Files

`fixtures/recipes/`:

- `portrait-relief.recipe.json` — the Portrait Relief default.
- `decorative-panel.recipe.json` — the Decorative Panel default.
- `signage.recipe.json` — the Signage default.
- `recipe-pack.json` — a 3-recipe pack (envelope shape) for testing
  `decodeEnvelope`.

## 3. Plugin API Draft (proposal, not loadable)

Goal: third-party toolpath strategies and importers as self-contained
plugins, loaded from `~/Library/Application Support/ShopPilot/Plugins/`.

### 3.1 Plugin manifest

A plugin is a directory with a `manifest.json`:

```json
{
  "apiVersion": 1,
  "id": "com.example.my-strategy",
  "name": "My Strategy",
  "kind": "toolpath-strategy",   // or "importer" | "post-template" | "gadget"
  "entry": "main.swift",         // or compiled binary
  "capabilities": ["vectors-in", "gcode-out"]
}
```

### 3.2 Contract (what ShopPilot promises a plugin)

1. **Input**: a JSON document on stdin describing the job — sheets, vectors
   (as path point arrays), material, tool, and the plugin's own params block.
2. **Output**: a JSON document on stdout — `{ "gcodeLines": [...],
   "estimatedTimeSeconds": n, "params": {...} }` — merged into the toolpath
   tree like any native strategy.
3. **Sandbox**: plugins run as child processes with a timeout; a hung plugin
   is killed and surfaced as a toolpath error, never a crash.
4. **Discovery**: plugins are enumerated at launch; a broken manifest is
   skipped with a console note (never blocks the app).
5. **Params**: plugin params are declared in the manifest
   (`"params": [{"key": "depth", "type": "number", "default": 3.0}]`) and the
   Cut inspector renders them generically (no per-plugin SwiftUI).

### 3.3 Open questions (v2.0)

- Code signing / notarization expectations for third-party plugins.
- Whether the JSON document format should match `.shoppilot` internals or a
  purpose-built `PluginJob` shape.
- Strategy-kind registration (tree badge, recalc branch) for plugin ops.

## 4. Verification

`ShopPilotVerify1006` proves the format + codec contract (round-trip,
envelope decode, sample files parse, forward-compatible unknown keys).
