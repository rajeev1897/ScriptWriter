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
}
