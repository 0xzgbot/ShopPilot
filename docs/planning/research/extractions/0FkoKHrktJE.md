# Extraction: 0FkoKHrktJE (enriched)

## capabilities_mentioned
- tool database dialogue (material+machine top controls)
- tool list expand/collapse
- tool geometry (diameter, flutes) vs cutting data (feeds/speeds)
- material management (add/copy/remove with warning)
- machine management (add/copy/remove)
- copy settings from another tool/material
- hide unset tools
- V-bit has angle param, end mill does not
- tool notes (postprocessor-output), toolpath groups

## workflow_steps
1. Tool database -> select material + machine (filters available tools) -> add/copy/remove materials (remove warns if cutting data attached) -> add/copy/remove machines -> add tool (default or custom: type, diameter, flutes) -> if grayed out: copy settings from existing material or enter spindle/feed/plunge + pass depth/stepover -> apply -> hide unset tools to declutter -> per-toolpath edit stays local

## parameters_concepts
- tool geometry (diameter, flutes, angle for V-bit)
- cutting data (spindle RPM, feed, plunge, pass depth, stepover)
- per material+machine matrix

## gotchas_warnings
- Tools grayed out = no cutting data for the active material+machine — add it or copy from another material
- Removing a material warns that associated cutting data is deleted
- One tool = multiple cutting-data sets (per material) — not separate tools
- Tool notes can be output by post processor — useful for 'cut in 3 passes' reminders

## lean_relevance
**must**

## notes
The tool database data model: geometry (static) x cutting data (per material+machine). ShopPilot's Tool DB seed (P1) should follow this exactly.
