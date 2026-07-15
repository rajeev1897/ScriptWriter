import { createElement } from "@lwc/engine-dom";
import { CurrentPageReference } from "lightning/navigation";
import ScriptEditor from "c/scriptEditor";
import loadScript from "@salesforce/apex/ScriptEditorController.loadScript";
import saveScript from "@salesforce/apex/ScriptEditorController.saveScript";

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
      savedAt: "2026-07-15T12:00:00.000Z"
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
      pageCount: 1
    });
    expect(saveScript.mock.calls[0][0].content).toContain("INT. OFFICE - DAY");
    expect(
      element.shadowRoot.querySelector(".save-status").textContent
    ).toContain("Saved");
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
  });
});
