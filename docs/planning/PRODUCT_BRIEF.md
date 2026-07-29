# ShopPilot — Product Brief

**Date:** 2026-07-28  
**Working name:** ShopPilot  
**Platform:** macOS (Apple Silicon first)  
**Category:** CNC router machine control (sender / pendant-class desktop app)

## Problem

Hobby and small-shop CNC router users on Mac often juggle Windows-centric senders, brittle serial tools, or browser UIs. They need a **native, safe, readable** control surface: connect, jog, zero, stream G-code, and stop instantly — without full CAM complexity.

## Solution

ShopPilot is a SwiftUI Mac app that:

1. Talks **USB serial** to GRBL/FluidNC-class controllers.
2. Streams existing **G-code** jobs with hold/resume/reset.
3. Shows live **status and console** diagnostics.
4. Saves **machine profiles** per router.
5. Includes a **software simulator** so agents and developers can build without hardware.

## Users

- Small shop / garage CNC router operators on Mac
- Makers who already generate G-code elsewhere (Fusion, VCarve, etc.)
- Local AI agents (Hermes) implementing features against the task board

## MVP success

Operator can, on simulator then on real hardware: connect → status OK → load fixture G-code → confirm Start → stream → Feed Hold → Resume → complete → Reset. Soft-limit warnings and always-on safety chrome present.

## Non-goals (MVP)

- Generating toolpaths from CAD
- Replacing LightBurn/slicers for lasers/printers (router focus first)
- Multi-axis specialty kinematics beyond standard XYZ router

## Related local context

- Desktop has other maker assets (e.g. Centauri Carbon, LightBurn files) — **out of scope for v1** unless later network/printer epics are opened in `HERMES_BUILD_TODO.md` Phase 6.
