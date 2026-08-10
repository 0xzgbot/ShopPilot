# ShopPilot Recipe & Plugin API — Implemented (SPK-1006)

> Status: **Implemented** — the JSON recipe format and the plugin ABI are
> both loadable and verified. The plugin contract below is the shipped ABI
> (child-process sandbox with timeout), not a proposal.

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

## 3. Plugin ABI (implemented, verified)

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
  "entry": "main.swift",         // or a compiled binary / shebang script
  "capabilities": ["vectors-in", "gcode-out"]
}
```

`params` declares the plugin's knobs (`key`/`type`/`defaultValue`); the Cut
inspector renders them generically. A manifest with `apiVersion != 1` or
missing id/name/entry is rejected at discovery and never fatal.

### 3.2 Contract (what ShopPilot promises a plugin)

1. **Input**: a JSON document on stdin — `PluginJobDocument`:
   `{ jobName, stockWidthMm, stockDepthMm, stockHeightMm, vectors:
   [{points:[{x,y}], isClosed}], params: {...} }`.
2. **Output**: a JSON document on stdout — `PluginOutput`:
   `{ gcodeLines: [...], estimatedTimeSeconds: n, params: {...} }` — injected
   into the toolpath tree as a normal operation node.
3. **Sandbox**: plugins run as child processes with a timeout (default 30s);
   a hung plugin is terminated and surfaced as a toolpath error, never a
   crash. `PluginRunner.run` implements the spawn → stdin → wait → kill.
4. **Discovery**: `PluginStore` enumerates plugin directories at launch
   (Application Support/ShopPilot/Plugins + the app bundle's Plugins dir);
   a broken manifest is skipped with a console note.
5. **Params**: plugin params are declared in the manifest
   (`"params": [{"key": "depth", "type": "number", "default": 3.0}]`) and
   merged from defaults into the job document at run time.

### 3.3 Shipped sample

`fixtures/plugins/dotgrid-engrave/` — a real toolpath-strategy plugin
(`manifest.json` + `main.swift`) that emits a peck-dot grid across the stock.
`ShopPilotVerifyPluginABI` runs it as a real child process and checks the
emitted G-code (markers, modal header, 4×3 grid on 40×30 stock = 12 plunges,
last dot at (35,25)), plus manifest rejection and the timeout kill.

### 3.4 Open questions (v2.0)

- Code signing / notarization expectations for third-party plugins.
- Strategy-kind registration (tree badge, recalc branch) for plugin ops —
  today plugin output is injected as an operation node with the plugin name;
  a dedicated `.plugin` StrategyKind would give it native badge/recalc.

## 4. Verification

`ShopPilotVerify1006` proves the format + codec contract (round-trip,
envelope decode, sample files parse, forward-compatible unknown keys).
