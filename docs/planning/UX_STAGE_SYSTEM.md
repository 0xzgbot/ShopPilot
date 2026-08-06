# ShopPilot UX — Stage System & Anti-Bloat Rules

## Problem the reference has (that we fix without removing features)

The reference is powerful but **visually dense**: large icon matrices, left design panel + right toolpath panel, frequent layout thrash, and many tools that 90% of sessions never touch. V12 improved unification; we go further with **stages + progressive disclosure**.

## Stage rail

| Stage | User intent | Primary tools (max ~12) | Browser default |
| --- | --- | --- | --- |
| **Setup** | Stock, origin, machine, keep-outs | Job type, dimensions, datum, machine pick | Sheets |
| **Design** | 2D artwork | Select, line, rect, circle, text, offset, boolean, import, node | Layers |
| **Model** | 3D relief collage | Select, shapes, import 3D, sculpt, combine, zero plane | Components |
| **Cut** | Strategies | Profile, pocket, drill, V-carve, 3D rough/finish, more strategies… | Toolpaths |
| **Preview** | Trust before cut | Simulate, material, time, proof image | Toolpaths |
| **Machine** | Physical execution | Connect, zero, hold, resume, run, console | Machine log |

### Stage transition behavior

- Entering **Cut** pins toolpath browser; soft-hides unused Model tools.  
- Entering **Machine** requires Preview “looks good” acknowledgment first time per session (skippable in prefs for pros).  
- **⌘K** always lists all commands regardless of stage.

## Inspector rules

1. One inspector only (right).  
2. Sections: **Essentials** → **Passes & motion** → **Advanced**.  
3. Numeric fields support expressions (`1/2`, `25.4/2`).  
4. Danger actions (delete toolpath, reset machine) need confirm.

## Command palette

Every reference-named operation must be findable:

- “Nest Parts”, “Photo V-Carve”, “Level Mirror Left to Right”, “Post Processor Management”  
Results show: name, stage, shortcut, one-line plain English.

## Recipes (not modes that lock features)

Recipes preconfigure; user can always leave recipe rails.

Examples:

- Calibration pattern (reference guide §05)  
- V-Carve letter sign  
- Raised panel  
- V-Carve inlay pair  
- Rotary fluted column  
- Laser cut sheet  

## Visual density budget

| Surface | Budget |
| --- | --- |
| Primary toolbar icons | ≤ 12 |
| Floating panels | ≤ 2 simultaneous |
| Modal dialogs | Prefer sheets/inspectors |
| Color for alerts | Red = machine/safety only |

## Copy tone

Shop floor clear:

- “Recalculate toolpath to match vectors” not “Invalidate cached kinematics.”  
- “Hold — pause spindle motion” on Feed Hold.

## Accessibility

- Large hit targets on Machine stage.  
- VoiceOver labels on Hold/Reset/Run.  
- Prefer contrast-safe dark theme for shop lighting.
