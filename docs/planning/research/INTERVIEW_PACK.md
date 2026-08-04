# Interview Pack — Sign-Shop Operator Research

**Date:** 2026-08-05 · **Status:** READY TO SEND. Recruiting + interviewing is a human task (blocked on the user); this pack is the complete kit. Derived from `SIGN_SHOP_OPERATOR_OPS.md` (proxy evidence + interview guide). **Do not invent answers** — fill the scoring sheet from real conversations only.

## What to send (copy-paste email)

**Subject:** 20 minutes on how you run your CNC — for a Mac sign-making tool

Hi [Name],

I'm building a lean Mac-native CNC design + carving app (V-carve, 3D carving, GRBL control) and I want to design it around how shops actually work — not how software vendors assume they work. You run [machine/shop type] and I'd love 20 minutes of your time, by phone or video, to ask about your workflow.

What I'll ask about (all quick, no prep needed):
- Your typical job from order to finished part — where you spend the most time
- How you zero the machine (touch-off plate? paper? off the material or the spoilboard?)
- Whether you preview before cutting, and what you look for
- The one job that went wrong and why
- The ONE thing you wish your software did automatically

No proprietary files, no screenshots of your work — I'm only collecting workflow facts and feature names. In return I'll send you a summary of findings + early access to the app when it's usable.

Are you open to it? If yes, any time this week that works?

Thanks,
[Name]
[Contact]

---

## Scoring sheet (one per operator)

**Operator:** \_\_\_\_\_\_\_\_\_\_ · **Shop type:** sign / plaque / 3D relief / other · **Machine:** \_\_\_\_\_\_\_\_\_\_ · **Controller:** GRBL / FluidNC / other · **CAM used:** \_\_\_\_\_\_\_\_\_\_

| # | Question | Answer (verbatim/notes) |
|---|---|---|
| 1 | Typical job order of ops (steps in order) | |
| 2 | Where do you spend most time? | |
| 3 | When do you decide toolpaths (design-first vs cutting-first)? | |
| 4 | Do you name files/toolpaths? What does the name tell you at the machine? | |
| 5 | How do you zero X/Y and Z? | |
| 6 | Ever cut into the spoilboard? What changed? | |
| 7 | What do you check on the machine before starting a run? | |
| 8 | Do you preview before cutting? What do you look for? | |
| 9 | Ever caught a real mistake in preview? What? | |
| 10 | What would make you trust software enough to skip a manual check? | |
| 11 | Worst job failure — cause (geometry/feeds/zeroing/hold-down/tool)? | |
| 12 | What do you warn new operators about first? | |
| 13 | ONE thing you wish software did automatically | |
| 14 | Features you never use (clutter) | |
| 15 | Tool changes: file-per-tool or ATC? How do you manage order? | |
| 16 | Z0 habit: material surface or spoilboard — and why? | |

### Post-interview coding (fill after, not during)

| Code | Count | Example quotes |
|---|---|---|
| Z0 mismatch failure | | |
| File-per-tool workflow | | |
| Preview-before-cut habit | | |
| Naming convention (order-encoded) | | |
| Feeds/speeds trial-and-error | | |
| Hold-down (tape/vacuum/clamps) | | |
| Wishlist: auto-* features | | |
| Clutter never used | | |

**Target:** 5–10 operators; 3 is the minimum for signal. **Merge results into** `SIGN_SHOP_OPERATOR_OPS.md` (append "Interview findings" section) and `FAILURE_MODE_LAB.md` (new FM evidence), then update `docs/planning/research/INDEX.md`.
