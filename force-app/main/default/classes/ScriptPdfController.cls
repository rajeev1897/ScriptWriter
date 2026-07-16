public with sharing class ScriptPdfController {
  public String title { get; private set; }
  public String mode { get; private set; }
  public List<BlockView> blocks { get; private set; }

  public ScriptPdfController() {
    blocks = new List<BlockView>();
    Id scriptId = ApexPages.currentPage().getParameters().get('id');
    if (scriptId == null) {
      title = 'Untitled script';
      mode = 'screenplay';
      return;
    }

    List<Script__c> scripts = [
      SELECT Id, Name, Type__c
      FROM Script__c
      WHERE Id = :scriptId
      WITH USER_MODE
      LIMIT 1
    ];
    if (scripts.isEmpty()) {
      title = 'Untitled script';
      mode = 'screenplay';
      return;
    }

    title = scripts[0].Name;
    mode = scripts[0].Type__c == 'Synopsis' ? 'synopsis' : 'screenplay';

    String content = ScriptBlockPersistenceService.loadOrMigrateWorkingContent(
      scriptId,
      mode
    );
    if (String.isBlank(content)) {
      return;
    }

    try {
      Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(
        content
      );
      if (document.containsKey('mode') && document.get('mode') != null) {
        mode = String.valueOf(document.get('mode'));
      }
      List<Object> rawBlocks = (List<Object>) document.get('blocks');
      if (rawBlocks == null) {
        return;
      }
      for (Object rawBlock : rawBlocks) {
        Map<String, Object> block = (Map<String, Object>) rawBlock;
        String value = block.get('value') == null
          ? ''
          : String.valueOf(block.get('value'));
        if (String.isBlank(value)) {
          continue;
        }
        BlockView view = new BlockView();
        view.blockType = normalizeBlockType(
          block.get('type') == null ? null : String.valueOf(block.get('type'))
        );
        view.value = value;
        view.cssClass = 'block block-' + view.blockType;
        blocks.add(view);
      }
    } catch (Exception ignored) {
      // Leave empty when content is invalid.
    }
  }

  private static String normalizeBlockType(String blockType) {
    if (
      blockType == 'scene-heading' ||
      blockType == 'action' ||
      blockType == 'character' ||
      blockType == 'dialogue' ||
      blockType == 'parenthetical' ||
      blockType == 'transition'
    ) {
      return blockType;
    }
    return 'action';
  }

  public class BlockView {
    public String blockType { get; set; }
    public String value { get; set; }
    public String cssClass { get; set; }
  }
}
