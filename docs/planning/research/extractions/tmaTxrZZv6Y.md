# Extraction: tmaTxrZZv6Y (enriched)

## capabilities_mentioned
- Machine management (add/edit/delete)
- post-processor auto-association by machine
- custom machine entry
- material management (add/copy/delete, presets)
- tool database (add default / custom tool)
- tool feeds/speeds per machine+material (pass depth, stepover, spindle, feed, plunge)
- grayed-out tool = missing feeds/speeds
- rapid clearance gap setting

## workflow_steps
1. Open machine & material setup -> manage machines (add machine, auto name/width/height/posts, or custom manual) -> save -> manage materials (add preset or custom name) -> manage tools (add default tool or custom: type, diameter, name) -> if tool grayed out, edit -> add feeds & speeds for machine+material (pass depth, stepover, spindle speed, feed rate, plunge rate) -> set rapid clearance gap

## parameters_concepts
- machine width/height
- post processor per machine
- tool type/diameter
- pass depth
- stepover
- spindle speed (RPM)
- feed rate
- plunge rate
- rapid clearance gap

## gotchas_warnings
- Grayed-out tool = no feeds/speeds for current machine+material — must add them
- Forgetting feeds/speeds is recoverable: add at toolpath creation time too
- Feeds/speeds are per machine AND per material — same tool, different data
- Custom posts can't be added to EasyCarve (only stock posts) — but full products support custom posts

## lean_relevance
**must**

## notes
The tool/machine/material database model: tool geometry (fixed) vs cutting data (varies by material+machine). This is the data model ShopPilot's Tool DB should mirror: tool geometry + per-material feeds/speeds.
