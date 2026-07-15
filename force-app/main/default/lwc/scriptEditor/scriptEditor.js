import { api, LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import loadScript from "@salesforce/apex/ScriptEditorController.loadScript";
import saveScript from "@salesforce/apex/ScriptEditorController.saveScript";

const AUTOSAVE_DELAY = 5000;

const SCREENPLAY_TYPES = [
  {
    value: "scene-heading",
    label: "Scene heading",
    placeholder: "INT. LOCATION - DAY"
  },
  { value: "action", label: "Action", placeholder: "Describe the action" },
  { value: "character", label: "Character", placeholder: "CHARACTER NAME" },
  { value: "dialogue", label: "Dialogue", placeholder: "Dialogue" },
  {
    value: "parenthetical",
    label: "Parenthetical",
    placeholder: "(quietly)"
  },
  { value: "transition", label: "Transition", placeholder: "CUT TO:" }
];

const TYPE_BY_VALUE = SCREENPLAY_TYPES.reduce((types, type) => {
  types[type.value] = type;
  return types;
}, {});

const ENTER_NEXT_TYPE = {
  "scene-heading": "action",
  action: "action",
  character: "dialogue",
  dialogue: "character",
  parenthetical: "dialogue",
  transition: "scene-heading"
};

export default class ScriptEditor extends LightningElement {
  mode = "screenplay";
  scriptTitle = "Untitled script";
  activeBlockId = 1;
  nextBlockId = 2;
  blockData = [{ id: 1, type: "scene-heading", value: "" }];
  saveState = "unavailable";
  saveMessage = "Open a script record to enable autosave";

  _recordId;
  isConnected = false;
  isLoaded = false;
  revision = 0;
  autosaveTimer;
  saveInFlight = false;
  trailingSaveRequested = false;

  modeOptions = [
    { label: "Screenplay", value: "screenplay" },
    { label: "Synopsis", value: "synopsis" }
  ];

  typeOptions = SCREENPLAY_TYPES.map(({ label, value }) => ({
    label,
    value
  }));

  @api
  get recordId() {
    return this._recordId;
  }

  set recordId(value) {
    this.setRecordId(value);
  }

  setRecordId(value) {
    if (value === this._recordId) {
      return;
    }

    this._recordId = value;
    this.resetPersistenceState();
    if (this.isConnected && value) {
      this.loadDocument();
    }
  }

  @wire(CurrentPageReference)
  handlePageReference(pageReference) {
    const urlRecordId = pageReference?.state?.c__recordId;
    if (urlRecordId && urlRecordId !== this.recordId) {
      this.setRecordId(urlRecordId);
    }
  }

  @api
  get value() {
    return JSON.stringify({
      mode: this.mode,
      blocks: this.blockData.map(({ id, type, value }) => ({
        id,
        type,
        value
      }))
    });
  }

  set value(documentValue) {
    this.applyDocumentValue(documentValue);
  }

  applyDocumentValue(documentValue) {
    if (!documentValue) {
      return;
    }

    try {
      const document =
        typeof documentValue === "string"
          ? JSON.parse(documentValue)
          : documentValue;
      const blocks = Array.isArray(document) ? document : document.blocks;

      if (!Array.isArray(blocks) || blocks.length === 0) {
        return;
      }

      this.mode = document.mode === "synopsis" ? "synopsis" : "screenplay";
      this.blockData = blocks.map((block, index) => ({
        id: index + 1,
        type: TYPE_BY_VALUE[block.type] ? block.type : "action",
        value: String(block.value ?? "")
      }));
      this.activeBlockId = 1;
      this.nextBlockId = this.blockData.length + 1;
    } catch {
      // Keep the current document when a consumer supplies invalid JSON.
    }
  }

  get blocks() {
    return this.blockData.map((block) => {
      const definition = TYPE_BY_VALUE[block.type];
      const isSynopsis = this.mode === "synopsis";

      return {
        ...block,
        label: isSynopsis ? "Synopsis" : definition.label,
        placeholder: isSynopsis
          ? "Write a concise summary of the story"
          : definition.placeholder,
        className: `script-block script-block_${isSynopsis ? "synopsis" : block.type} ${
          block.id === this.activeBlockId ? "script-block_active" : ""
        }`
      };
    });
  }

  get isScreenplay() {
    return this.mode === "screenplay";
  }

  get wordCount() {
    const text = this.blockData
      .map((block) => block.value)
      .join(" ")
      .trim();
    return text ? text.split(/\s+/).length : 0;
  }

  get blockCount() {
    return this.blockData.length;
  }

  get saveStatusClass() {
    return `save-status save-status_${this.saveState}`;
  }

  get hasSaveError() {
    return this.saveState === "error";
  }

  connectedCallback() {
    this.isConnected = true;
    if (this.recordId) {
      this.loadDocument();
    }
  }

  disconnectedCallback() {
    this.isConnected = false;
    this.clearAutosaveTimer();
  }

  renderedCallback() {
    this.template
      .querySelectorAll("textarea.block-input")
      .forEach((textarea) => {
        const block = this.blockData.find(
          (item) => item.id === Number(textarea.dataset.id)
        );
        if (block && textarea.value !== block.value) {
          textarea.value = block.value;
        }
        this.autoGrow(textarea);
      });
  }

  autoGrow(textarea) {
    textarea.style.height = "auto";
    textarea.style.height = `${textarea.scrollHeight}px`;
  }

  handleModeChange(event) {
    this.mode = event.detail.value;
    this.emitChange();
  }

  handleBlockFocus(event) {
    this.activeBlockId = Number(event.currentTarget.dataset.id);
  }

  handleInput(event) {
    const id = Number(event.target.dataset.id);
    const value = event.target.value;
    this.blockData = this.blockData.map((block) => {
      return block.id === id ? { ...block, value } : block;
    });
    this.autoGrow(event.target);
    this.emitChange();
  }

  handleTypeChange(event) {
    this.setBlockType(Number(event.target.dataset.id), event.detail.value);
  }

  handleToolbarClick(event) {
    this.setBlockType(this.activeBlockId, event.currentTarget.dataset.type);
    this.focusBlock(this.activeBlockId);
  }

  handleAddBlock() {
    const activeIndex = this.blockData.findIndex(
      (block) => block.id === this.activeBlockId
    );
    const currentType = this.blockData[activeIndex]?.type ?? "action";
    this.insertBlockAfter(activeIndex, ENTER_NEXT_TYPE[currentType]);
  }

  handleDeleteBlock(event) {
    event.stopPropagation();
    this.removeBlock(Number(event.currentTarget.dataset.id));
  }

  handleKeyDown(event) {
    const id = Number(event.target.dataset.id);
    const index = this.blockData.findIndex((block) => block.id === id);

    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault();
      this.insertBlockAfter(index, ENTER_NEXT_TYPE[this.blockData[index].type]);
    } else if (event.key === "Tab" && this.isScreenplay) {
      event.preventDefault();
      const direction = event.shiftKey ? -1 : 1;
      const currentTypeIndex = SCREENPLAY_TYPES.findIndex(
        (type) => type.value === this.blockData[index].type
      );
      const nextIndex =
        (currentTypeIndex + direction + SCREENPLAY_TYPES.length) %
        SCREENPLAY_TYPES.length;
      this.setBlockType(id, SCREENPLAY_TYPES[nextIndex].value);
    } else if (
      event.key === "Backspace" &&
      event.target.value === "" &&
      this.blockData.length > 1
    ) {
      event.preventDefault();
      this.removeBlock(id);
    }
  }

  setBlockType(id, type) {
    if (!TYPE_BY_VALUE[type]) {
      return;
    }
    this.blockData = this.blockData.map((block) => {
      return block.id === id ? { ...block, type } : block;
    });
    this.emitChange();
  }

  insertBlockAfter(index, type = "action") {
    const newBlock = { id: this.nextBlockId++, type, value: "" };
    const insertAt = index < 0 ? this.blockData.length : index + 1;
    this.blockData = [
      ...this.blockData.slice(0, insertAt),
      newBlock,
      ...this.blockData.slice(insertAt)
    ];
    this.activeBlockId = newBlock.id;
    this.emitChange();
    this.focusBlock(newBlock.id);
  }

  removeBlock(id) {
    if (this.blockData.length === 1) {
      return;
    }
    const index = this.blockData.findIndex((block) => block.id === id);
    this.blockData = this.blockData.filter((block) => block.id !== id);
    const focusIndex = Math.max(0, index - 1);
    this.activeBlockId = this.blockData[focusIndex].id;
    this.emitChange();
    this.focusBlock(this.activeBlockId);
  }

  focusBlock(id) {
    Promise.resolve().then(() => {
      this.template.querySelector(`textarea[data-id="${id}"]`)?.focus();
    });
  }

  emitChange() {
    this.revision += 1;
    this.scheduleAutosave();
    this.dispatchEvent(
      new CustomEvent("contentchange", {
        detail: {
          mode: this.mode,
          blocks: this.blockData.map(({ id, type, value }) => ({
            id,
            type,
            value
          }))
        },
        bubbles: true,
        composed: true
      })
    );
  }

  resetPersistenceState() {
    this.clearAutosaveTimer();
    this.isLoaded = false;
    this.trailingSaveRequested = false;
    this.revision = 0;
    if (this.recordId) {
      this.saveState = "loading";
      this.saveMessage = "Loading…";
    } else {
      this.saveState = "unavailable";
      this.saveMessage = "Open a script record to enable autosave";
    }
  }

  async loadDocument() {
    const recordId = this.recordId;
    const loadRevision = this.revision;
    this.saveState = "loading";
    this.saveMessage = "Loading…";

    try {
      const result = await loadScript({ scriptId: recordId });
      if (recordId !== this.recordId) {
        return;
      }

      this.scriptTitle = result.title || "Untitled script";
      if (this.revision === loadRevision && result.content) {
        this.applyDocumentValue(result.content);
      }
      if (result.mode) {
        this.mode = result.mode === "synopsis" ? "synopsis" : "screenplay";
      }
      this.isLoaded = true;

      if (this.revision !== loadRevision) {
        this.scheduleAutosave();
      } else if (result.savedAt) {
        this.showSavedStatus(result.savedAt);
      } else {
        this.saveState = "saved";
        this.saveMessage = "Autosave ready";
      }
    } catch (error) {
      if (recordId !== this.recordId) {
        return;
      }
      this.isLoaded = false;
      this.showSaveError(error);
    }
  }

  scheduleAutosave() {
    this.clearAutosaveTimer();
    if (!this.recordId) {
      this.saveState = "unavailable";
      this.saveMessage = "Open a script record to enable autosave";
      return;
    }

    this.saveState = "dirty";
    this.saveMessage = "Unsaved changes";
    if (!this.isLoaded) {
      return;
    }

    // Debouncing is intentional: persist only after five idle seconds.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.autosaveTimer = setTimeout(
      () => this.performAutosave(),
      AUTOSAVE_DELAY
    );
  }

  clearAutosaveTimer() {
    if (this.autosaveTimer) {
      clearTimeout(this.autosaveTimer);
      this.autosaveTimer = undefined;
    }
  }

  async performAutosave() {
    this.autosaveTimer = undefined;
    if (!this.recordId || !this.isLoaded) {
      return;
    }
    if (this.saveInFlight) {
      this.trailingSaveRequested = true;
      return;
    }

    const recordId = this.recordId;
    const savedRevision = this.revision;
    const content = this.value;
    this.saveInFlight = true;
    this.saveState = "saving";
    this.saveMessage = "Saving…";

    try {
      const result = await saveScript({
        scriptId: recordId,
        content,
        formatMetadata: JSON.stringify({
          schemaVersion: 1,
          mode: this.mode
        }),
        wordCount: this.wordCount,
        pageCount: this.wordCount === 0 ? 0 : Math.ceil(this.wordCount / 250),
        mode: this.mode
      });

      if (recordId !== this.recordId) {
        return;
      }
      if (savedRevision === this.revision) {
        this.showSavedStatus(result.savedAt);
      } else {
        this.saveState = "dirty";
        this.saveMessage = "Unsaved changes";
      }
    } catch (error) {
      if (recordId === this.recordId) {
        this.showSaveError(error);
      }
    } finally {
      this.saveInFlight = false;
      if (this.trailingSaveRequested && this.recordId && this.isLoaded) {
        this.trailingSaveRequested = false;
        this.performAutosave();
      }
    }
  }

  showSavedStatus(savedAt) {
    const savedDate = new Date(savedAt);
    const time = Number.isNaN(savedDate.getTime())
      ? ""
      : savedDate.toLocaleTimeString([], {
          hour: "numeric",
          minute: "2-digit"
        });
    this.saveState = "saved";
    this.saveMessage = time ? `Saved ${time}` : "Saved";
  }

  showSaveError(error) {
    const message =
      error?.body?.message || error?.message || "An unexpected error occurred";
    this.saveState = "error";
    this.saveMessage = `Couldn’t save — ${message}`;
  }
}
