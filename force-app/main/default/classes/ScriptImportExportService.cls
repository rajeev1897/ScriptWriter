public with sharing class ScriptImportExportService {
  public class ParsedDocument {
    public String mode;
    public List<Block> blocks = new List<Block>();
  }

  public class Block {
    public Integer id;
    public String type;
    public String value;
  }

  public static ParsedDocument parsePlainText(
    String rawText,
    String preferredMode
  ) {
    ParsedDocument document = new ParsedDocument();
    document.mode = preferredMode == 'synopsis' ? 'synopsis' : 'screenplay';

    if (String.isBlank(rawText)) {
      Block emptyBlock = new Block();
      emptyBlock.id = 1;
      emptyBlock.type = document.mode == 'synopsis'
        ? 'action'
        : 'scene-heading';
      emptyBlock.value = '';
      document.blocks.add(emptyBlock);
      return document;
    }

    List<String> lines = rawText.replace('\r\n', '\n')
      .replace('\r', '\n')
      .split('\n');
    Integer nextId = 1;

    if (document.mode == 'synopsis') {
      Block synopsisBlock = new Block();
      synopsisBlock.id = nextId++;
      synopsisBlock.type = 'action';
      synopsisBlock.value = String.join(lines, '\n').trim();
      document.blocks.add(synopsisBlock);
      return document;
    }

    String previousType;
    for (String line : lines) {
      String trimmed = line == null ? '' : line.trim();
      if (String.isBlank(trimmed)) {
        continue;
      }

      Block block = new Block();
      block.id = nextId++;
      block.type = inferScreenplayType(trimmed, previousType);
      block.value = trimmed;
      document.blocks.add(block);
      previousType = block.type;
    }

    if (document.blocks.isEmpty()) {
      Block emptyBlock = new Block();
      emptyBlock.id = 1;
      emptyBlock.type = 'scene-heading';
      emptyBlock.value = '';
      document.blocks.add(emptyBlock);
    }

    return document;
  }

  public static String toPlainText(String contentJson) {
    if (String.isBlank(contentJson)) {
      return '';
    }

    Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(
      contentJson
    );
    String mode = (String) document.get('mode');
    List<Object> rawBlocks = (List<Object>) document.get('blocks');
    if (rawBlocks == null || rawBlocks.isEmpty()) {
      return '';
    }

    List<String> lines = new List<String>();
    for (Object rawBlock : rawBlocks) {
      Map<String, Object> block = (Map<String, Object>) rawBlock;
      String value = block.get('value') == null
        ? ''
        : String.valueOf(block.get('value'));
      if (mode == 'synopsis') {
        lines.add(value);
      } else {
        lines.add(value);
        lines.add('');
      }
    }

    return String.join(lines, '\n').trim();
  }

  public static String toEditorJson(ParsedDocument document) {
    Map<String, Object> payload = new Map<String, Object>{
      'mode' => document.mode,
      'blocks' => new List<Object>()
    };
    List<Object> blocks = (List<Object>) payload.get('blocks');
    for (Block block : document.blocks) {
      blocks.add(
        new Map<String, Object>{
          'id' => block.id,
          'type' => block.type,
          'value' => block.value
        }
      );
    }
    return JSON.serialize(payload);
  }

  public static Integer countWords(String contentJson) {
    String text = toPlainText(contentJson);
    if (String.isBlank(text)) {
      return 0;
    }
    return text.trim().split('\\s+').size();
  }

  private static String inferScreenplayType(String line, String previousType) {
    String upper = line.toUpperCase();
    if (
      upper.startsWith('INT.') ||
      upper.startsWith('EXT.') ||
      upper.startsWith('I/E.') ||
      upper.startsWith('INT/EXT')
    ) {
      return 'scene-heading';
    }
    if (
      upper.endsWith('TO:') ||
      upper == 'FADE OUT.' ||
      upper == 'FADE IN:' ||
      upper == 'CUT TO:' ||
      upper == 'DISSOLVE TO:'
    ) {
      return 'transition';
    }
    if (line.startsWith('(') && line.endsWith(')')) {
      return 'parenthetical';
    }
    if (
      upper == line &&
      line.length() <= 40 &&
      !line.contains('.') &&
      !line.contains(',')
    ) {
      return 'character';
    }
    if (previousType == 'character' || previousType == 'parenthetical') {
      return 'dialogue';
    }
    return 'action';
  }
}
