# Agent 05 — Migration, Tests, Cleanup

## Role

Migrate existing File/Legacy documents into scenes/blocks; harden tests; document the new source of truth.

## Prerequisites

Agents 01–04 deployed and committed.

## Branch

`feature/script-block-model`

## Build

### Migration

- On `loadScript`, if script has File/Legacy content but **no** `Script_Block__c` rows:
  - Parse editor JSON
  - Create scenes/blocks
  - Mark document `Storage_Mode__c` appropriately (e.g. keep File as backup or set a `Migrated` indicator)
- Optional invocable/batch for bulk migrate — only if cheap; lazy migrate on open is enough for MVP

### Source of truth

- Reading: blocks first
- Writing: blocks always
- `Script_Document__c.Content__c` no longer required for large scripts (may clear or leave backup under limit)
- Working File JSON optional going forward (prefer blocks); keep version snapshots as ContentVersion

### Tests

- Coverage ≥75% for new/changed Apex
- Jest covers dirty autosave + import
- Validate full package deploy

### Docs

- Update `docs/agents/script-block-model/README.md` status to **Complete**
- Short note in project README if present: where script text lives now

### Cleanup (careful)

- Do not delete objects still referenced
- May deprecate writing to working ContentDocument on autosave (versions still use ContentVersion)

## Acceptance

- Opening an old File-backed script populates scenes/blocks once
- New edits dirty-autosave to blocks
- Manual save still snapshots to Files
- Full deploy green

## End of agent

1. Deploy + tests
2. Commit: `Migrate scripts to scene block storage.`
3. Summarize remaining manual QA steps for the user
4. Do **not** merge to `main` unless asked
