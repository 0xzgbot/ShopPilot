# ADR-001 — Application stack

**Status:** Accepted  
**Date:** 2026-07-28

## Context

ShopPilot is a Mac-native CNC router control app. Needs low-latency serial I/O, a reliable UI for safety controls, and a stack local agents (Hermes) can implement on Apple Silicon.

## Decision

- **UI:** SwiftUI, macOS 14+  
- **Language:** Swift  
- **I/O:** Serial via IOKit and/or ORSSerialPort  
- **Architecture:** Modular targets — App / Core / Serial / Tests  
- **Dev path:** Simulator transport before real hardware  

## Alternatives considered

| Option | Why not for v1 |
| --- | --- |
| Electron | Heavier; serial bridging more awkward; less native safety UX |
| Tauri | Strong option, but user chose native SwiftUI |
| Python + PyQt | Fast prototyping; weaker “Mac app” packaging/feel |

## Consequences

- Best macOS integration and performance  
- Requires Xcode for agents  
- Serial permissions and code signing need documentation for distribution later  
