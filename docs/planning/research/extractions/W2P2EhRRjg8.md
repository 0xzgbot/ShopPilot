# Extraction: W2P2EhRRjg8 (enriched)

## capabilities_mentioned
- machine configuration dialogue
- kickstart wizard on first run
- machine DB (name/manufacturer/model/controller/width/height/units)
- post processor association (required warning)
- default post per machine
- post versioning (latest vs pinned)
- custom post install to custom directory
- post view/change log/customize (edit copy)
- make default for laser
- machine search online

## workflow_steps
1. First run: kickstart wizard or migration prompt -> search machine online (auto machine+posts+default feeds/speeds) OR add custom machine (name, model, controller, width, height, units) -> associate post processors (warning if none: benefits = default-post, organization, version control) -> select posts from DB (G-Code inch/mm, arcs) -> optionally pin older post version (warning) -> make default -> apply

## parameters_concepts
- machine width/height/units
- post processor per machine
- post version (latest/pinned)
- controller type
- default post

## gotchas_warnings
- Machine with NO associated post triggers warning — software falls back to full post list otherwise
- Pinning an old post version shows a warning and blocks auto-updates to that post
- Customize = copy of a post (pen icon) stored in custom postp dir; edits never touch stock post
- Posts are per-machine; default post = first in save dialog

## lean_relevance
**must**

## notes
Post processor management = per-machine dialect mapping with version pinning and custom copies. ShopPilot's GRBL-class posts map directly; version pinning is the 'trusted golden' concept.
