# Agent 03 — LWC Dirty-Block Autosave

## Role

LWC agent. Keep the current editor UX, but autosave only dirty blocks every 5 seconds.

## Prerequisites

Agents 01–02 deployed and committed.

## Branch

`feature/script-block-model`

## Build

### Dirty tracking in `scriptEditor`

- Give each block a stable id (keep integer ids or switch to Salesforce Ids after first save)
- On text/type/insert/delete/mode change: mark affected block(s) dirty
- After 5s debounce: call Apex with **only dirty blocks** (+ deletes list if needed)
- Clear dirty flags only for blocks successfully saved
- Trailing queue while save in flight (preserve current behavior)
- Status UI unchanged: Unsaved / Saving / Saved / error
- Manual Save version + Cmd/Ctrl+S still call full Manual save

### Apex contract (extend if needed)

```js
saveScript({
  scriptId,
  content, // full JSON still useful for Manual/Import
  dirtyBlocks: [{ id, type, value, sequence, sceneKey? }],
  deletedBlockIds: [],
  mode,
  wordCount,
  pageCount,
  saveSource: 'Autosave' | 'Manual' | ...
})
```

### After first autosave of new blocks

- Apex should return saved block Id map so LWC can replace temporary ids
- Avoid duplicate inserts on next autosave

### Tests

- Jest: dirty-only payload after edit
- Jest: second edit resets timer
- Jest: Manual still sends Manual source
- Keep existing keyboard/format tests green

## Do not

- Break upload/download buttons (stub OK if Apex changes in Agent 04)
- Migrate legacy docs

## Acceptance

- Editing one dialogue block autosaves only that block (verify via mock call args)
- Full document still loads into the editor
- Deploy succeeds; Jest green

## End of agent

1. Deploy LWC + Apex if controller signature changed
2. Commit: `Autosave only dirty script blocks from the editor.`
3. Stop and report
