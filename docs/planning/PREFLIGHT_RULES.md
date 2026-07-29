# ShopPilot Preflight Rules

**Source:** Aspire V12 error strings and validation messages, mapped to actionable preflight checks.  
**Purpose:** Block toolpath generation on invalid geometry with plain-English fix CTAs.

---

## Rule Set

### R001 — Open Vector Gaps
| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any polyline or arc where start ≠ end point within tolerance (1e-6 units) |
| **Aspire Equivalent** | "Vector path is not closed" / "Open contour detected" |
| **Plain English** | "This shape has a gap — the toolpath can't follow an open line." |
| **Fix CTA** | Show node handles at gap endpoints with "Close Gap" button (connects endpoints) |

### R002 — Self-Intersecting Contours
| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any shape where edges cross each other (line-line intersection within bounds) |
| **Aspire Equivalent** | "Self-intersecting path may produce unexpected results" |
| **Plain English** | "This shape crosses itself — the toolpath would cut in two places at once." |
| **Fix CTA** | Highlight intersecting segments, offer "Split at Intersections" (boolean union) |

### R003 — Zero-Length Segments
| Field | Value |
|-------|-------|
| **Severity** | Warning (allows export with override) |
| **Trigger** | Any line segment where start == end point exactly |
| **Aspire Equivalent** | "Degenerate vector element" |
| **Plain English** | "This is a zero-length line — it won't cut anything." |
| **Fix CTA** | Highlight and offer "Remove Zero-Length Segments" |

### R004 — Duplicate Vectors
| Field | Value |
|-------|-------|
| **Severity** | Warning (allows export with override) |
| **Trigger** | Two or more shapes occupying the same bounding box within tolerance |
| **Aspire Equivalent** | "Duplicate geometry detected" |
| **Plain English** | "This shape is duplicated — you'll cut it twice." |
| **Fix CTA** | Highlight duplicates, offer "Merge Duplicates" (boolean weld) |

### R005 — Toolpath Outside Stock Bounds
| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any toolpath segment outside the defined stock rectangle |
| **Aspire Equivalent** | "Toolpath extends beyond material" |
| **Plain English** | "This cut goes off your material — you'd cut into empty space." |
| **Fix CTA** | Highlight out-of-bounds segments, offer "Clip to Stock" or "Expand Stock" |

### R006 — Zero Tool Diameter
| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any toolpath using a tool with diameter ≤ 0 |
| **Aspire Equivalent** | "Invalid tool size" |
| **Plain English** | "This tool has no cutting edge — select an endmill or V-bit." |
| **Fix CTA** | Open tool database picker, pre-select valid tools |

### R007 — No Tool Selected for Strategy
| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Profile/Pocket/Drill/V-Carve strategy with no tool assigned |
| **Aspire Equivalent** | "No cutting tool selected" |
| **Plain English** | "You haven't chosen a cutting tool for this operation." |
| **Fix CTA** | Open tool selector in the strategy panel |

### R008 — Feed Rate Exceeds Machine Limit
| Field | Value |
|-------|-------|
| **Severity** | Warning (allows export with override) |
| **Trigger** | Any feed rate exceeding the machine profile's max RPM or max travel speed |
| **Aspire Equivalent** | "Feed rate exceeds machine capability" |
| **Plain English** | "This cut is faster than your machine can handle." |
| **Fix CTA** | Show current vs. limit, offer "Reduce to Safe Speed" |

### R009 — Depth Exceeds Stock Thickness
| Field | Value |
|-------|-------|
| **Severity** | Error (blocks export) |
| **Trigger** | Any cutting depth deeper than the stock thickness setting |
| **Aspire Equivalent** | "Cutting depth exceeds material thickness" |
| **Plain English** | "This cut goes through your entire piece — you'll damage the table." |
| **Fix CTA** | Show current vs. stock, offer "Reduce Depth" or "Expand Stock" |

### R010 — Tab Spacing Too Tight
| Field | Value |
|-------|-------|
| **Severity** | Warning (allows export with override) |
| **Trigger** | Profile tabs spaced closer than the tool diameter apart |
| **Aspire Equivalent** | "Tabs may not hold material securely" |
| **Plain English** | "Your tabs are too close together — they might not hold the piece." |
| **Fix CTA** | Show tab layout, offer "Auto-Adjust Tab Spacing" |

---

## Preflight Check Flow

1. User clicks "Run Preflight" (or attempts to export)
2. System runs all rules against current geometry + toolpath settings
3. Results displayed in a panel:
   - **Errors** (red): Must fix before export
   - **Warnings** (yellow): Can override with confirmation
4. Each issue shows:
   - Plain English description
   - Visual highlight on the canvas
   - One-click fix CTA (where applicable)
5. Export button remains disabled until all errors are resolved

## Integration Points

- **SPK-0211**: Vector Preflight Doctor — implements R001-R004 checks in geometry kernel
- **SPK-0212**: Preflight plain-English fix actions — implements CTA buttons and canvas highlighting
- **SPK-0307**: Block export while dirty — integrates preflight into export gate
- **SPK-0604**: Preflight blocks V-Carve on open vectors with fix CTA — Phase G acceptance test
