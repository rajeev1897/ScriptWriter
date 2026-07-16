@IsTest
private class ScriptPdfControllerTest {
  @IsTest
  static void rendersBlocksFromSceneBlockStorage() {
    Script__c script = new Script__c(
      Name = 'PDF Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;

    ScriptEditorController.saveScript(
      script.Id,
      '{"mode":"screenplay","blocks":[{"id":1,"type":"scene-heading","value":"INT. OFFICE - DAY"},{"id":2,"type":"action","value":"Lights flicker."}]}',
      '{"schemaVersion":3,"mode":"screenplay"}',
      5,
      1,
      'screenplay',
      'Autosave',
      null,
      null
    );

    PageReference pdfPage = Page.ScriptPdf;
    pdfPage.getParameters().put('id', script.Id);
    Test.setCurrentPage(pdfPage);

    Test.startTest();
    ScriptPdfController controller = new ScriptPdfController();
    Test.stopTest();

    Assert.areEqual('PDF Script', controller.title);
    Assert.areEqual('screenplay', controller.mode);
    Assert.areEqual(2, controller.blocks.size());
    Assert.areEqual('scene-heading', controller.blocks[0].blockType);
    Assert.areEqual('INT. OFFICE - DAY', controller.blocks[0].value);
    Assert.areEqual('action', controller.blocks[1].blockType);
    Assert.areEqual('Lights flicker.', controller.blocks[1].value);
  }

  @IsTest
  static void migratesFileDocumentWhenNoBlocks() {
    Script__c script = new Script__c(
      Name = 'Legacy PDF Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;

    String content =
      '{"mode":"screenplay","blocks":[{"id":1,"type":"action","value":"Legacy line."}]}';
    Script_Document__c document = new Script_Document__c(
      Script__c = script.Id,
      Storage_Mode__c = 'File',
      Content__c = content
    );
    insert document;

    PageReference pdfPage = Page.ScriptPdf;
    pdfPage.getParameters().put('id', script.Id);
    Test.setCurrentPage(pdfPage);

    Test.startTest();
    ScriptPdfController controller = new ScriptPdfController();
    Test.stopTest();

    Assert.areEqual('Legacy PDF Script', controller.title);
    Assert.areEqual(1, controller.blocks.size());
    Assert.areEqual('Legacy line.', controller.blocks[0].value);
    Assert.areEqual(
      1,
      [SELECT COUNT() FROM Script_Block__c WHERE Script__c = :script.Id]
    );
    Assert.areEqual(
      'Migrated',
      [
          SELECT Storage_Mode__c
          FROM Script_Document__c
          WHERE Id = :document.Id
        ]
        .Storage_Mode__c
    );
  }

  @IsTest
  static void skipsBlankBlocksAndNormalizesUnknownTypes() {
    Script__c script = new Script__c(
      Name = 'Normalize PDF Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;

    ScriptEditorController.saveScript(
      script.Id,
      '{"mode":"screenplay","blocks":[{"id":1,"type":"scene-heading","value":"INT. OFFICE - DAY"},{"id":2,"type":"action","value":""},{"id":3,"type":"unknown","value":"Fallback action."}]}',
      '{"schemaVersion":3,"mode":"screenplay"}',
      4,
      1,
      'screenplay',
      'Autosave',
      null,
      null
    );

    PageReference pdfPage = Page.ScriptPdf;
    pdfPage.getParameters().put('id', script.Id);
    Test.setCurrentPage(pdfPage);

    Test.startTest();
    ScriptPdfController controller = new ScriptPdfController();
    Test.stopTest();

    Assert.areEqual(2, controller.blocks.size());
    Assert.areEqual('scene-heading', controller.blocks[0].blockType);
    Assert.areEqual('action', controller.blocks[1].blockType);
    Assert.areEqual('Fallback action.', controller.blocks[1].value);
    Assert.areEqual('block block-action', controller.blocks[1].cssClass);
  }

  @IsTest
  static void handlesMissingIdAndEmptyContent() {
    PageReference missingIdPage = Page.ScriptPdf;
    Test.setCurrentPage(missingIdPage);

    ScriptPdfController missingIdController = new ScriptPdfController();
    Assert.areEqual('Untitled script', missingIdController.title);
    Assert.areEqual('screenplay', missingIdController.mode);
    Assert.areEqual(0, missingIdController.blocks.size());

    Script__c emptyScript = new Script__c(
      Name = 'Empty PDF Script',
      Type__c = 'Synopsis',
      Status__c = 'Draft'
    );
    insert emptyScript;

    PageReference emptyPage = Page.ScriptPdf;
    emptyPage.getParameters().put('id', emptyScript.Id);
    Test.setCurrentPage(emptyPage);

    ScriptPdfController emptyController = new ScriptPdfController();
    Assert.areEqual('Empty PDF Script', emptyController.title);
    Assert.areEqual('synopsis', emptyController.mode);
    Assert.areEqual(0, emptyController.blocks.size());
  }

  @IsTest
  static void rendersSynopsisModeAndNullBlocksSafely() {
    Script__c script = new Script__c(
      Name = 'Synopsis PDF Script',
      Type__c = 'Synopsis',
      Status__c = 'Draft'
    );
    insert script;

    ScriptEditorController.saveScript(
      script.Id,
      '{"mode":"synopsis","blocks":[{"id":1,"type":"action","value":"A quiet town."},{"id":2,"type":"dialogue","value":"Hello."}]}',
      '{"schemaVersion":3,"mode":"synopsis"}',
      4,
      1,
      'synopsis',
      'Autosave',
      null,
      null
    );

    PageReference pdfPage = Page.ScriptPdf;
    pdfPage.getParameters().put('id', script.Id);
    Test.setCurrentPage(pdfPage);

    Test.startTest();
    ScriptPdfController controller = new ScriptPdfController();
    Test.stopTest();

    Assert.areEqual('synopsis', controller.mode);
    Assert.areEqual(2, controller.blocks.size());
    Assert.areEqual('A quiet town.', controller.blocks[0].value);
    Assert.areEqual('block block-dialogue', controller.blocks[1].cssClass);
  }

  @IsTest
  static void rendersAllScreenplayBlockTypes() {
    Script__c script = new Script__c(
      Name = 'Full Format PDF Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;

    ScriptEditorController.saveScript(
      script.Id,
      '{"mode":"screenplay","blocks":[' +
        '{"id":1,"type":"scene-heading","value":"INT. OFFICE - DAY"},' +
        '{"id":2,"type":"action","value":"Lights flicker."},' +
        '{"id":3,"type":"character","value":"MORGAN"},' +
        '{"id":4,"type":"parenthetical","value":"(quietly)"},' +
        '{"id":5,"type":"dialogue","value":"We should leave."},' +
        '{"id":6,"type":"transition","value":"CUT TO:"}' +
        ']}',
      '{"schemaVersion":3,"mode":"screenplay"}',
      12,
      1,
      'screenplay',
      'Autosave',
      null,
      null
    );

    PageReference pdfPage = Page.ScriptPdf;
    pdfPage.getParameters().put('id', script.Id);
    Test.setCurrentPage(pdfPage);

    Test.startTest();
    ScriptPdfController controller = new ScriptPdfController();
    Test.stopTest();

    Assert.areEqual(6, controller.blocks.size());
    Assert.areEqual('scene-heading', controller.blocks[0].blockType);
    Assert.areEqual('action', controller.blocks[1].blockType);
    Assert.areEqual('character', controller.blocks[2].blockType);
    Assert.areEqual('parenthetical', controller.blocks[3].blockType);
    Assert.areEqual('dialogue', controller.blocks[4].blockType);
    Assert.areEqual('transition', controller.blocks[5].blockType);
    Assert.areEqual('block block-transition', controller.blocks[5].cssClass);
  }

  @IsTest
  static void leavesBlocksEmptyForMissingScriptAndInvalidPayload() {
    String missingScriptId =
      String.valueOf(Script__c.SObjectType.getDescribe().getKeyPrefix()) +
      '000000000001AAA';
    PageReference missingScriptPage = Page.ScriptPdf;
    missingScriptPage.getParameters().put('id', missingScriptId);
    Test.setCurrentPage(missingScriptPage);

    ScriptPdfController missingScriptController = new ScriptPdfController();
    Assert.areEqual('Untitled script', missingScriptController.title);
    Assert.areEqual(0, missingScriptController.blocks.size());

    Script__c script = new Script__c(
      Name = 'Invalid Payload PDF Script',
      Type__c = 'Screenplay',
      Status__c = 'Draft'
    );
    insert script;
    insert new Script_Document__c(
      Script__c = script.Id,
      Storage_Mode__c = 'Legacy',
      Content__c = '{"mode":"screenplay","blocks":null}'
    );

    PageReference pdfPage = Page.ScriptPdf;
    pdfPage.getParameters().put('id', script.Id);
    Test.setCurrentPage(pdfPage);

    Test.startTest();
    ScriptPdfController controller = new ScriptPdfController();
    Test.stopTest();

    Assert.areEqual('Invalid Payload PDF Script', controller.title);
    Assert.areEqual(0, controller.blocks.size());
  }
}
