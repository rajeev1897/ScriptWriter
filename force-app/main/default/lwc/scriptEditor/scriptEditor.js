import { api, LightningElement, wire } from "lwc";
import { CurrentPageReference } from "lightning/navigation";
import loadScript from "@salesforce/apex/ScriptEditorController.loadScript";
import saveScript from "@salesforce/apex/ScriptEditorController.saveScript";
import importPlainText from "@salesforce/apex/ScriptEditorController.importPlainText";
import exportPlainText from "@salesforce/apex/ScriptEditorController.exportPlainText";
import exportPdf from "@salesforce/apex/ScriptEditorController.exportPdf";

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

function isPersistedBlockId(id) {
  const value = String(id ?? "");
  return value.length === 15 || value.length === 18;
}

export default class ScriptEditor extends LightningElement {
  mode = "screenplay";
  scriptTitle = "Untitled script";
  activeBlockId = "1";
  nextBlockId = 2;
  blockData = [{ id: "1", type: "scene-heading", value: "" }];
  saveState = "unavailable";
  saveMessage = "Open a script record to enable autosave";
  pdfUrl;

  _recordId;
  isConnected = false;
  isLoaded = false;
  revision = 0;
  autosaveTimer;
  saveInFlight = false;
  queuedSaveSource;
  dirtyBlockIds = new Set();
  deletedBlockIds = [];

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
        id: block.id == null ? String(index + 1) : String(block.id),
        type: TYPE_BY_VALUE[block.type] ? block.type : "action",
        value: String(block.value ?? "")
      }));
      this.activeBlockId = this.blockData[0].id;
      this.nextBlockId = this.nextTempBlockId();
      this.clearDirtyTracking();
    } catch {
      // Keep the current document when a consumer supplies invalid JSON.
    }
  }

  nextTempBlockId() {
    let highest = 0;
    this.blockData.forEach((block) => {
      const asNumber = Number(block.id);
      if (Number.isInteger(asNumber) && asNumber > highest) {
        highest = asNumber;
      }
    });
    return Math.max(highest + 1, this.nextBlockId);
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

  get isSaveDisabled() {
    return !this.recordId || !this.isLoaded;
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
          (item) => String(item.id) === String(textarea.dataset.id)
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
    this.markAllBlocksDirty();
    this.emitChange();
  }

  handleEditorKeyDown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
      event.preventDefault();
      this.handleManualSave();
    }
  }

  handleManualSave() {
    if (this.isSaveDisabled) {
      return;
    }
    this.clearAutosaveTimer();
    this.performSave("Manual");
  }

  handleUploadClick() {
    if (this.isSaveDisabled) {
      return;
    }
    this.template.querySelector(".upload-input")?.click();
  }

  async handleFileSelected(event) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file || this.isSaveDisabled) {
      return;
    }

    this.saveState = "saving";
    this.saveMessage = "Importing…";

    try {
      const plainText = await this.readFileAsText(file);
      const result = await importPlainText({
        scriptId: this.recordId,
        plainText,
        fileName: file.name,
        mode: this.mode
      });
      if (result?.content) {
        this.applyDocumentValue(result.content);
      }
      this.pdfUrl = result.pdfUrl || this.pdfUrl;
      this.revision += 1;
      this.showSavedStatus(result.savedAt, true);
      this.saveMessage = "Imported and version saved";
    } catch (error) {
      this.showSaveError(error);
    }
  }

  readFileAsText(file) {
    if (typeof file.text === "function") {
      return file.text();
    }

    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result || ""));
      reader.onerror = () => reject(reader.error || new Error("Unable to read file"));
      reader.readAsText(file);
    });
  }

  async handleDownloadTxt() {
    if (this.isSaveDisabled) {
      return;
    }

    this.saveState = "saving";
    this.saveMessage = "Preparing download…";

    try {
      const result = await exportPlainText({ scriptId: this.recordId });
      this.pdfUrl = result.pdfUrl || this.pdfUrl;
      this.downloadBrowserFile(
        result.fileName || `${this.scriptTitle || "script"}.txt`,
        result.plainText || "",
        "text/plain"
      );
      this.saveState = "saved";
      this.saveMessage = "Downloaded .txt";
    } catch (error) {
      this.showSaveError(error);
    }
  }

  async handleDownloadPdf() {
    if (this.isSaveDisabled) {
      return;
    }

    this.saveState = "saving";
    this.saveMessage = "Preparing PDF…";

    try {
      const result = await exportPdf({ scriptId: this.recordId });
      this.pdfUrl = result.pdfUrl || this.pdfUrl;
      const url =
        result.downloadUrl ||
        this.pdfUrl ||
        `/apex/ScriptPdf?id=${this.recordId}`;
      window.open(url, "_blank");
      this.saveState = "saved";
      this.saveMessage = "Downloaded PDF";
    } catch (error) {
      this.showSaveError(error);
    }
  }

  downloadBrowserFile(fileName, content, mimeType) {
    const blob = new Blob([content], { type: mimeType });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = fileName;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  handleBlockFocus(event) {
    this.activeBlockId = String(event.currentTarget.dataset.id);
  }

  handleInput(event) {
    const id = String(event.target.dataset.id);
    const value = event.target.value;
    this.blockData = this.blockData.map((block) => {
      return String(block.id) === id ? { ...block, value } : block;
    });
    this.markBlocksDirty([id]);
    this.autoGrow(event.target);
    this.emitChange();
  }

  handleTypeChange(event) {
    this.setBlockType(String(event.target.dataset.id), event.detail.value);
  }

  handleToolbarClick(event) {
    this.setBlockType(this.activeBlockId, event.currentTarget.dataset.type);
    this.focusBlock(this.activeBlockId);
  }

  handleAddBlock() {
    const activeIndex = this.blockData.findIndex(
      (block) => String(block.id) === String(this.activeBlockId)
    );
    const currentType = this.blockData[activeIndex]?.type ?? "action";
    this.insertBlockAfter(activeIndex, ENTER_NEXT_TYPE[currentType]);
  }

  handleDeleteBlock(event) {
    event.stopPropagation();
    this.removeBlock(String(event.currentTarget.dataset.id));
  }

  handleKeyDown(event) {
    const id = String(event.target.dataset.id);
    const index = this.blockData.findIndex(
      (block) => String(block.id) === id
    );

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
    const blockId = String(id);
    this.blockData = this.blockData.map((block) => {
      return String(block.id) === blockId ? { ...block, type } : block;
    });
    this.markBlocksDirty([blockId]);
    this.emitChange();
  }

  insertBlockAfter(index, type = "action") {
    const newBlock = {
      id: String(this.nextBlockId++),
      type,
      value: ""
    };
    const insertAt = index < 0 ? this.blockData.length : index + 1;
    this.blockData = [
      ...this.blockData.slice(0, insertAt),
      newBlock,
      ...this.blockData.slice(insertAt)
    ];
    this.activeBlockId = newBlock.id;
    // Insert shifts sequences for following blocks.
    this.markAllBlocksDirty();
    this.emitChange();
    this.focusBlock(newBlock.id);
  }

  removeBlock(id) {
    if (this.blockData.length === 1) {
      return;
    }
    const blockId = String(id);
    const index = this.blockData.findIndex(
      (block) => String(block.id) === blockId
    );
    this.blockData = this.blockData.filter(
      (block) => String(block.id) !== blockId
    );
    this.dirtyBlockIds.delete(blockId);
    if (isPersistedBlockId(blockId)) {
      this.deletedBlockIds = [...this.deletedBlockIds, blockId];
    }
    const focusIndex = Math.max(0, index - 1);
    this.activeBlockId = this.blockData[focusIndex].id;
    // Delete shifts sequences for remaining blocks.
    this.markAllBlocksDirty();
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
    this.queuedSaveSource = undefined;
    this.revision = 0;
    this.clearDirtyTracking();
    if (this.recordId) {
      this.saveState = "loading";
      this.saveMessage = "Loading…";
    } else {
      this.saveState = "unavailable";
      this.saveMessage = "Open a script record to enable autosave";
    }
  }

  clearDirtyTracking() {
    this.dirtyBlockIds = new Set();
    this.deletedBlockIds = [];
  }

  markBlocksDirty(ids) {
    ids.forEach((id) => {
      if (id != null) {
        this.dirtyBlockIds.add(String(id));
      }
    });
  }

  markAllBlocksDirty() {
    this.markBlocksDirty(this.blockData.map((block) => block.id));
  }

  buildDirtyBlocksPayload() {
    return this.blockData
      .map((block, index) => ({
        id: String(block.id),
        type: block.type,
        value: block.value,
        sequence: index + 1
      }))
      .filter((block) => this.dirtyBlockIds.has(block.id));
  }

  applyBlockIdMap(blockIdMap) {
    if (!blockIdMap || typeof blockIdMap !== "object") {
      return;
    }

    const entries = Object.entries(blockIdMap);
    if (entries.length === 0) {
      return;
    }

    const idMap = new Map(
      entries.map(([clientId, serverId]) => [
        String(clientId),
        String(serverId)
      ])
    );

    this.blockData = this.blockData.map((block) => {
      const mappedId = idMap.get(String(block.id));
      return mappedId ? { ...block, id: mappedId } : block;
    });

    const remappedDirty = new Set();
    this.dirtyBlockIds.forEach((id) => {
      remappedDirty.add(idMap.get(String(id)) || String(id));
    });
    this.dirtyBlockIds = remappedDirty;

    if (idMap.has(String(this.activeBlockId))) {
      this.activeBlockId = idMap.get(String(this.activeBlockId));
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
      this.pdfUrl = result.pdfUrl;
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
    this.performSave("Autosave");
  }

  async performSave(saveSource) {
    this.autosaveTimer = undefined;
    if (!this.recordId || !this.isLoaded) {
      return;
    }
    if (this.saveInFlight) {
      if (saveSource === "Manual" || !this.queuedSaveSource) {
        this.queuedSaveSource = saveSource;
      }
      return;
    }

    const recordId = this.recordId;
    const savedRevision = this.revision;
    const content = this.value;
    const isAutosave = saveSource === "Autosave";
    const dirtyBlocksPayload = isAutosave ? this.buildDirtyBlocksPayload() : [];
    const deletedSnapshot = isAutosave ? [...this.deletedBlockIds] : [];
    const dirtySnapshotIds = dirtyBlocksPayload.map((block) => block.id);

    if (
      isAutosave &&
      dirtyBlocksPayload.length === 0 &&
      deletedSnapshot.length === 0
    ) {
      return;
    }

    this.saveInFlight = true;
    this.saveState = "saving";
    this.saveMessage = saveSource === "Manual" ? "Saving version…" : "Saving…";

    try {
      const saveRequest = {
        scriptId: recordId,
        content,
        formatMetadata: JSON.stringify({
          schemaVersion: 3,
          mode: this.mode
        }),
        wordCount: this.wordCount,
        pageCount: this.wordCount === 0 ? 0 : Math.ceil(this.wordCount / 250),
        mode: this.mode,
        saveSource
      };

      if (isAutosave) {
        saveRequest.dirtyBlocks = JSON.stringify(dirtyBlocksPayload);
        saveRequest.deletedBlockIds = JSON.stringify(deletedSnapshot);
      }

      const result = await saveScript(saveRequest);

      if (recordId !== this.recordId) {
        return;
      }
      if (result?.pdfUrl) {
        this.pdfUrl = result.pdfUrl;
      }

      this.applyBlockIdMap(result?.blockIdMap);

      if (isAutosave) {
        const deletedSet = new Set(deletedSnapshot.map(String));
        this.deletedBlockIds = this.deletedBlockIds.filter(
          (id) => !deletedSet.has(String(id))
        );
        // Only clear dirty flags when nothing changed during the request.
        // Otherwise keep remapped dirty ids for the trailing autosave.
        if (savedRevision === this.revision) {
          dirtySnapshotIds.forEach((id) => {
            const mappedId =
              result?.blockIdMap?.[id] != null
                ? String(result.blockIdMap[id])
                : String(id);
            this.dirtyBlockIds.delete(String(id));
            this.dirtyBlockIds.delete(mappedId);
          });
        }
      } else if (savedRevision === this.revision) {
        this.clearDirtyTracking();
      }

      if (savedRevision === this.revision) {
        this.showSavedStatus(
          result.savedAt,
          saveSource === "Manual" || saveSource === "Import"
        );
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
      if (this.queuedSaveSource && this.recordId && this.isLoaded) {
        const queuedSaveSource = this.queuedSaveSource;
        this.queuedSaveSource = undefined;
        this.performSave(queuedSaveSource);
      }
    }
  }

  showSavedStatus(savedAt, versionCreated = false) {
    const savedDate = new Date(savedAt);
    const time = Number.isNaN(savedDate.getTime())
      ? ""
      : savedDate.toLocaleTimeString([], {
          hour: "numeric",
          minute: "2-digit"
        });
    this.saveState = "saved";
    const label = versionCreated ? "Version saved" : "Saved";
    this.saveMessage = time ? `${label} ${time}` : label;
  }

  showSaveError(error) {
    const message =
      error?.body?.message || error?.message || "An unexpected error occurred";
    this.saveState = "error";
    this.saveMessage = `Couldn’t save — ${message}`;
  }
}
