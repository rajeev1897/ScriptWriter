# Agent 02 — Apex Persistence (Scenes + Blocks)

## Role

Apex agent. Implement server-side load/save against `Script_Scene__c` / `Script_Block__c` while keeping the LWC JSON contract `{ mode, blocks[] }` working.

## Prerequisites

Agent 01 deployed and committed on `feature/script-block-model`.

## Branch

Continue on `feature/script-block-model`.

## Build

### New services (preferred)

- `ScriptBlockPersistenceService.cls`
  - `loadDocument(scriptId)` → editor JSON assembled from scenes/blocks ordered by Sequence
  - `autosaveBlocks(scriptId, dirtyBlocks, mode, wordCount, pageCount)` → upsert/update only changed blocks; ensure scene rows exist; update `Script__c.Last_Saved_At__c`; **no** `Script_Version__c`
  - Map LWC types (`scene-heading`, `action`, …) ↔ picklist labels

### Scene derivation rules

- A new `scene-heading` block starts/belongs to a scene
- Non-heading blocks attach to the current scene
- If no scene heading yet, create a default scene Sequence 1
- Keep `Script_Scene__c.Scene_Heading__c` in sync with heading block text when type is Scene Heading

### Controller changes (`ScriptEditorController`)

- `loadScript`: prefer scenes/blocks if any exist; else fall back to File/`Content__c` via existing `ScriptDocumentStorageService`
- `saveScript`:
  - `Autosave` → call dirty-block autosave API (accept optional `dirtyBlocks` JSON; if omitted, treat full content as all dirty for compatibility)
  - `Manual`/`Import`/`Export` → still allowed, but full version snapshot can remain stubbed until Agent 04 if needed; at minimum Manual must persist all blocks then create version **or** clearly document handoff to Agent 04
- Keep USER_MODE/SYSTEM_MODE patterns consistent with current File storage code

### Tests

- Apex tests for create/update dirty blocks, load order, no version on autosave

## Do not

- Rewrite the entire LWC UI (Agent 03)
- Remove File storage yet (Agent 05)
- Unrelated Prettier edits

## Acceptance

- Apex tests pass on deploy validate
- Autosave path does not insert `Script_Version__c`
- Load returns blocks in sequence order

## End of agent

1. Deploy + run specified Apex tests
2. Commit: `Add scene and block Apex persistence.`
3. Stop and report
