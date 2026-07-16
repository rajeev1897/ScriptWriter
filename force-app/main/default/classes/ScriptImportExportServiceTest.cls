@IsTest
private class ScriptImportExportServiceTest {
  @IsTest
  static void parsePlainTextInfersScreenplayBlocks() {
    String plainText = 'INT. CAFE - NIGHT\n\nALEX\n(quietly)\nWe should leave.\n\nCUT TO:';

    Test.startTest();
    ScriptImportExportService.ParsedDocument parsed = ScriptImportExportService.parsePlainText(
      plainText,
      'screenplay'
    );
    Test.stopTest();

    Assert.areEqual('screenplay', parsed.mode);
    Assert.areEqual(5, parsed.blocks.size());
    Assert.areEqual('scene-heading', parsed.blocks[0].type);
    Assert.areEqual('character', parsed.blocks[1].type);
    Assert.areEqual('parenthetical', parsed.blocks[2].type);
    Assert.areEqual('dialogue', parsed.blocks[3].type);
    Assert.areEqual('transition', parsed.blocks[4].type);
  }

  @IsTest
  static void roundTripPlainTextPreservesBody() {
    String content = '{"mode":"screenplay","blocks":[{"id":1,"type":"action","value":"She opens the door."}]}';

    Test.startTest();
    String plainText = ScriptImportExportService.toPlainText(content);
    Integer wordCount = ScriptImportExportService.countWords(content);
    Test.stopTest();

    Assert.isTrue(plainText.contains('She opens the door.'));
    Assert.areEqual(4, wordCount);
  }
}
