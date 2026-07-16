import { createElement } from "@lwc/engine-dom";
import { CurrentPageReference } from "lightning/navigation";
import ScriptEditor from "c/scriptEditor";
import loadScript from "@salesforce/apex/ScriptEditorController.loadScript";
import saveScript from "@salesforce/apex/ScriptEditorController.saveScript";
import importPlainText from "@salesforce/apex/ScriptEditorController.importPlainText";
import exportPlainText from "@salesforce/apex/ScriptEditorController.exportPlainText";

jest.mock(
  "@salesforce/apex/ScriptEditorController.loadScript",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ScriptEditorController.saveScript",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ScriptEditorController.importPlainText",
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  "@salesforce/apex/ScriptEditorController.exportPlainText",
  () => ({ default: jest.fn() }),
  { virtual: true }
);

function createComponent(value, recordId) {
  const element = createElement("c-script-editor", {
    is: ScriptEditor
  });
  if (value) {
    element.value = value;
  }
  if (recordId) {
    element.recordId = recordId;
  }
  document.body.appendChild(element);
  return element;
}

async function flushPromises() {
  await Promise.resolve();
  await Promise.resolve();
}

describe("c-script-editor", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it("starts with a scene heading block", () => {
    const element = createComponent();
    const textarea = element.shadowRoot.querySelector("textarea");

    expect(textarea.placeholder).toBe("INT. LOCATION - DAY");
    expect(
      element.shadowRoot.querySelector(".script-block_scene-heading")
    ).not.toBeNull();
  });

  it("creates the expected next screenplay block on Enter", async () => {
    const element = createComponent();
    const firstBlock = element.shadowRoot.querySelector("textarea");

    firstBlock.dispatchEvent(
      new KeyboardEvent("keydown", {
        key: "Enter",
        bubbles: true,
        cancelable: true
      })
    );
    await flushPromises();

    const blocks = element.shadowRoot.querySelectorAll("textarea");
    expect(blocks).toHaveLength(2);
    expect(blocks[1].placeholder).toBe("Describe the action");
  });

  it("updates a block from the format toolbar", async () => {
    const element = createComponent();
    const dialogueButton = element.shadowRoot.querySelector(
      'button[data-type="dialogue"]'
    );

    dialogueButton.click();
    await flushPromises();

    expect(
      element.shadowRoot.querySelector(".script-block_dialogue")
    ).not.toBeNull();
  });

  it("emits the serializable document when content changes", () => {
    const element = createComponent();
    const listener = jest.fn();
    element.addEventListener("contentchange", listener);
    const textarea = element.shadowRoot.querySelector("textarea");

    textarea.value = "INT. OFFICE - DAY";
    textarea.dispatchEvent(new InputEvent("input", { bubbles: true }));

    expect(listener).toHaveBeenCalledTimes(1);
    expect(listener.mock.calls[0][0].detail.blocks[0]).toMatchObject({
      type: "scene-heading",
      value: "INT. OFFICE - DAY"
    });
  });

  it("loads an existing document through the public value property", () => {
    const element = createComponent(
      JSON.stringify({
        mode: "screenplay",
        blocks: [
          { type: "character", value: "MORGAN" },
          { type: "dialogue", value: "Ready when you are." }
        ]
      })
    );
    const textareas = element.shadowRoot.querySelectorAll("textarea");

    expect(textareas).toHaveLength(2);
    expect(textareas[0].value).toBe("MORGAN");
    expect(textareas[1].value).toBe("Ready when you are.");
  });

  it("opens the URL script in its Type-defined editor mode", async () => {
    loadScript.mockResolvedValue({
      title: "Story outline",
      mode: "synopsis",
      content: null,
      savedAt: null
    });
    const element = createComponent();

    CurrentPageReference.emit({
      state: { c__recordId: "a01000000000001AAA" }
    });
    await flushPromises();

    expect(loadScript).toHaveBeenCalledWith({
      scriptId: "a01000000000001AAA"
    });
    expect(
      element.shadowRoot.querySelector(".script-block_synopsis")
    ).not.toBeNull();
  });

  it("autosaves five seconds after the last change", async () => {
    jest.useFakeTimers();
    loadScript.mockResolvedValue({
      title: "Test script",
      content: null,
      savedAt: null
    });
    saveScript.mockResolvedValue({
      savedAt: "2026-07-15T12:00:00.000Z",
      blockIdMap: { 1: "a0B000000000001AAA" }
    });
    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();
    const textarea = element.shadowRoot.querySelector("textarea");

    textarea.value = "INT. OFFICE - DAY";
    textarea.dispatchEvent(new InputEvent("input", { bubbles: true }));
    jest.advanceTimersByTime(4999);
    expect(saveScript).not.toHaveBeenCalled();

    jest.advanceTimersByTime(1);
    await flushPromises();

    expect(saveScript).toHaveBeenCalledTimes(1);
    expect(saveScript.mock.calls[0][0]).toMatchObject({
      scriptId: "a01000000000001AAA",
      mode: "screenplay",
      wordCount: 4,
      pageCount: 1,
      saveSource: "Autosave"
    });
    expect(saveScript.mock.calls[0][0].content).toContain("INT. OFFICE - DAY");
    const dirtyBlocks = JSON.parse(saveScript.mock.calls[0][0].dirtyBlocks);
    expect(dirtyBlocks).toHaveLength(1);
    expect(dirtyBlocks[0]).toMatchObject({
      id: "1",
      type: "scene-heading",
      value: "INT. OFFICE - DAY",
      sequence: 1
    });
    expect(JSON.parse(saveScript.mock.calls[0][0].deletedBlockIds)).toEqual([]);
    expect(
      element.shadowRoot.querySelector(".save-status").textContent
    ).toContain("Saved");
  });

  it("autosaves only the dirty dialogue block after an edit", async () => {
    jest.useFakeTimers();
    loadScript.mockResolvedValue({
      title: "Test script",
      content: JSON.stringify({
        mode: "screenplay",
        blocks: [
          {
            id: "a0B000000000001AAA",
            type: "scene-heading",
            value: "INT. OFFICE - DAY"
          },
          {
            id: "a0B000000000002AAA",
            type: "character",
            value: "MORGAN"
          },
          {
            id: "a0B000000000003AAA",
            type: "dialogue",
            value: "Hello"
          }
        ]
      }),
      savedAt: "2026-07-15T11:00:00.000Z"
    });
    saveScript.mockResolvedValue({
      savedAt: "2026-07-15T12:00:00.000Z"
    });
    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();

    const dialogue = element.shadowRoot.querySelectorAll("textarea")[2];
    dialogue.value = "Ready when you are.";
    dialogue.dispatchEvent(new InputEvent("input", { bubbles: true }));
    jest.advanceTimersByTime(5000);
    await flushPromises();

    expect(saveScript).toHaveBeenCalledTimes(1);
    const dirtyBlocks = JSON.parse(saveScript.mock.calls[0][0].dirtyBlocks);
    expect(dirtyBlocks).toEqual([
      {
        id: "a0B000000000003AAA",
        type: "dialogue",
        value: "Ready when you are.",
        sequence: 3
      }
    ]);
    expect(saveScript.mock.calls[0][0].saveSource).toBe("Autosave");
  });

  it("creates a manual version from the Save button", async () => {
    loadScript.mockResolvedValue({
      title: "Test script",
      content: null,
      savedAt: null
    });
    saveScript.mockResolvedValue({
      savedAt: "2026-07-15T12:00:00.000Z",
      versionId: "a03000000000001AAA"
    });
    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();

    element.shadowRoot.querySelector(".save-button").click();
    await flushPromises();

    expect(saveScript).toHaveBeenCalledWith(
      expect.objectContaining({ saveSource: "Manual" })
    );
    expect(saveScript.mock.calls[0][0].dirtyBlocks).toBeUndefined();
    expect(saveScript.mock.calls[0][0].deletedBlockIds).toBeUndefined();
    expect(
      element.shadowRoot.querySelector(".save-status").textContent
    ).toContain("Version saved");
  });

  it("creates a manual version with Ctrl+S", async () => {
    loadScript.mockResolvedValue({
      title: "Test script",
      content: null,
      savedAt: null
    });
    saveScript.mockResolvedValue({
      savedAt: "2026-07-15T12:00:00.000Z",
      versionId: "a03000000000001AAA"
    });
    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();
    const shortcut = new KeyboardEvent("keydown", {
      key: "s",
      ctrlKey: true,
      bubbles: true,
      cancelable: true
    });

    element.shadowRoot.querySelector("textarea").dispatchEvent(shortcut);
    await flushPromises();

    expect(shortcut.defaultPrevented).toBe(true);
    expect(saveScript).toHaveBeenCalledWith(
      expect.objectContaining({ saveSource: "Manual" })
    );
  });

  it("resets the autosave delay after another edit", async () => {
    jest.useFakeTimers();
    loadScript.mockResolvedValue({
      title: "Test script",
      content: null,
      savedAt: null
    });
    saveScript.mockResolvedValue({
      savedAt: "2026-07-15T12:00:00.000Z"
    });
    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();
    const textarea = element.shadowRoot.querySelector("textarea");

    textarea.value = "First";
    textarea.dispatchEvent(new InputEvent("input", { bubbles: true }));
    jest.advanceTimersByTime(4000);
    textarea.value = "Second";
    textarea.dispatchEvent(new InputEvent("input", { bubbles: true }));
    jest.advanceTimersByTime(4999);

    expect(saveScript).not.toHaveBeenCalled();
    jest.advanceTimersByTime(1);
    await flushPromises();
    expect(saveScript).toHaveBeenCalledTimes(1);
  });

  it("shows an accessible error when autosave fails", async () => {
    jest.useFakeTimers();
    loadScript.mockResolvedValue({
      title: "Test script",
      content: null,
      savedAt: null
    });
    saveScript.mockRejectedValue({
      body: { message: "Network unavailable" }
    });
    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();
    const textarea = element.shadowRoot.querySelector("textarea");

    textarea.value = "Draft";
    textarea.dispatchEvent(new InputEvent("input", { bubbles: true }));
    jest.advanceTimersByTime(5000);
    await flushPromises();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert.textContent).toContain("Couldn’t save — Network unavailable");
  });

  it("queues a trailing save for edits made during a save", async () => {
    jest.useFakeTimers();
    let resolveFirstSave;
    loadScript.mockResolvedValue({
      title: "Test script",
      content: null,
      savedAt: null
    });
    saveScript
      .mockImplementationOnce(
        () =>
          new Promise((resolve) => {
            resolveFirstSave = resolve;
          })
      )
      .mockResolvedValue({
        savedAt: "2026-07-15T12:01:00.000Z"
      });
    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();
    const textarea = element.shadowRoot.querySelector("textarea");

    textarea.value = "First";
    textarea.dispatchEvent(new InputEvent("input", { bubbles: true }));
    jest.advanceTimersByTime(5000);
    await Promise.resolve();
    expect(saveScript).toHaveBeenCalledTimes(1);

    textarea.value = "Second";
    textarea.dispatchEvent(new InputEvent("input", { bubbles: true }));
    jest.advanceTimersByTime(5000);
    resolveFirstSave({ savedAt: "2026-07-15T12:00:00.000Z" });
    await flushPromises();

    expect(saveScript).toHaveBeenCalledTimes(2);
    expect(saveScript.mock.calls[1][0].content).toContain("Second");
    const dirtyBlocks = JSON.parse(saveScript.mock.calls[1][0].dirtyBlocks);
    expect(dirtyBlocks[0].value).toBe("Second");
  });

  it("preserves Salesforce block ids when loading a document", async () => {
    loadScript.mockResolvedValue({
      title: "Test script",
      content: JSON.stringify({
        mode: "screenplay",
        blocks: [
          {
            id: "a0B000000000001AAA",
            type: "action",
            value: "She opens the door."
          }
        ]
      }),
      savedAt: "2026-07-15T11:00:00.000Z"
    });
    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();

    expect(
      element.shadowRoot.querySelector("textarea").getAttribute("data-id")
    ).toBe("a0B000000000001AAA");
  });

  it("imports a plain text file into the editor", async () => {
    loadScript.mockResolvedValue({
      title: "Test script",
      content: null,
      savedAt: null,
      pdfUrl: "/apex/ScriptPdf?id=a01000000000001AAA"
    });
    importPlainText.mockResolvedValue({
      savedAt: "2026-07-15T12:00:00.000Z",
      content:
        '{"mode":"screenplay","blocks":[{"id":1,"type":"scene-heading","value":"INT. OFFICE - DAY"}]}',
      pdfUrl: "/apex/ScriptPdf?id=a01000000000001AAA"
    });
    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();
    const input = element.shadowRoot.querySelector(".upload-input");
    const file = {
      name: "draft.txt",
      text: jest.fn().mockResolvedValue("INT. OFFICE - DAY")
    };
    Object.defineProperty(input, "files", {
      configurable: true,
      value: [file]
    });

    input.dispatchEvent(new CustomEvent("change"));
    await flushPromises();
    await flushPromises();

    expect(importPlainText).toHaveBeenCalledWith(
      expect.objectContaining({
        scriptId: "a01000000000001AAA",
        fileName: "draft.txt",
        plainText: "INT. OFFICE - DAY"
      })
    );
    expect(element.shadowRoot.querySelector("textarea").value).toBe(
      "INT. OFFICE - DAY"
    );
  });

  it("downloads plain text through export", async () => {
    loadScript.mockResolvedValue({
      title: "Test script",
      content: null,
      savedAt: null,
      pdfUrl: "/apex/ScriptPdf?id=a01000000000001AAA"
    });
    exportPlainText.mockResolvedValue({
      fileName: "Test script.txt",
      plainText: "INT. OFFICE - DAY",
      pdfUrl: "/apex/ScriptPdf?id=a01000000000001AAA"
    });
    const createObjectURL = jest.fn(() => "blob:mock");
    const revokeObjectURL = jest.fn();
    global.URL.createObjectURL = createObjectURL;
    global.URL.revokeObjectURL = revokeObjectURL;
    const click = jest
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => {});

    const element = createComponent(null, "a01000000000001AAA");
    await flushPromises();
    element.shadowRoot.querySelector(".download-txt-button").click();
    await flushPromises();

    expect(exportPlainText).toHaveBeenCalledWith({
      scriptId: "a01000000000001AAA"
    });
    expect(createObjectURL).toHaveBeenCalled();
    expect(click).toHaveBeenCalled();
    click.mockRestore();
  });
});
