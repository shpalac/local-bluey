/// Tool-call contract between the LLM brain and the Mac's native control layer,
/// ported from RealtimeHost.tools in the original Swift app.
///
/// Text-only LLMs receive these as system-prompt instructions and answer with
/// a JSON block: `{"tool": "<name>", "arguments": {...}}` (one per reply).
library;

class ToolCall {
  ToolCall(this.name, this.arguments);

  final String name;
  final Map<String, dynamic> arguments;
}

class ToolSpec {
  const ToolSpec(
    this.name,
    this.description, {
    this.properties = const {},
    this.required = const [],
  });

  final String name;
  final String description;
  final Map<String, Map<String, Object>> properties;
  final List<String> required;
}

const _gridX = {
  'type': 'number',
  'description': '0 = left edge, 1000 = right edge of the screen',
};
const _gridY = {
  'type': 'number',
  'description': '0 = top edge, 1000 = bottom edge of the screen',
};
const _targetId = {
  'type': 'string',
  'description':
      'An id from look_at_screen (C, L or W). Leave out to use x and y.',
};

const List<ToolSpec> kTools = [
  ToolSpec(
    'look_at_screen',
    "Take a fresh look at the user's screen. Returns the frontmost app, its clickable controls (C ids), every piece of text (lines L#, words W#) with positions on a 0-1000 grid, and a screenshot. Call this before pointing or acting, and again whenever the screen may have changed.",
  ),
  ToolSpec(
    'point_at',
    "Fly your cursor to something on screen and keep pointing there while you talk about it. Use the most specific id (a single word or number over a whole line). Call it right before you mention the thing.",
    properties: {'target_id': _targetId},
    required: ['target_id'],
  ),
  ToolSpec(
    'point_at_spot',
    "Point at something that isn't text (a shape, arrow, chart bar, image) using its position on the 0-1000 grid of the last screenshot.",
    properties: {'x': _gridX, 'y': _gridY},
    required: ['x', 'y'],
  ),
  ToolSpec(
    'stop_pointing',
    "Bring your cursor back home when you're done pointing.",
  ),
  ToolSpec(
    'go_to_sleep',
    "Go back to quietly following the user's mouse with your eyes. Use when the user says bye, thanks that's all, or asks you to sleep.",
  ),
  ToolSpec(
    'click',
    'Click something on the screen with your cursor. Prefer a target id; use x and y on the 0-1000 grid for things without an id. Returns the screen afterwards.',
    properties: {
      'target_id': _targetId,
      'x': _gridX,
      'y': _gridY,
      'double': {
        'type': 'boolean',
        'description': 'Double-click instead of a single click.',
      },
      'right': {
        'type': 'boolean',
        'description': 'Right-click (for context menus).',
      },
    },
  ),
  ToolSpec(
    'type_text',
    'Type text into whatever is focused, like a keyboard. Click the field first. A newline presses Return.',
    properties: {
      'text': {'type': 'string'},
      'press_return': {
        'type': 'boolean',
        'description': 'Press Return after typing.',
      },
    },
    required: ['text'],
  ),
  ToolSpec(
    'press_keys',
    'Press a key or keyboard shortcut, like "cmd+t", "cmd+l", "return", "escape", "tab", "down" or "cmd+shift+n".',
    properties: {
      'keys': {'type': 'string'},
    },
    required: ['keys'],
  ),
  ToolSpec(
    'scroll',
    'Scroll the page under a target or spot (or the middle of the screen).',
    properties: {
      'direction': {
        'type': 'string',
        'enum': ['up', 'down', 'left', 'right'],
      },
      'amount': {
        'type': 'number',
        'description': 'How far, 1 (a little) to 10 (a lot). Default 3.',
      },
      'target_id': _targetId,
      'x': _gridX,
      'y': _gridY,
    },
    required: ['direction'],
  ),
  ToolSpec(
    'drag',
    'Drag from one place to another (move a shape, select text, drag a slider). Use ids or 0-1000 grid positions.',
    properties: {
      'from_id': _targetId,
      'from_x': _gridX,
      'from_y': _gridY,
      'to_id': _targetId,
      'to_x': _gridX,
      'to_y': _gridY,
    },
  ),
  ToolSpec(
    'open_app',
    'Open an app or switch to it by name, like "Safari", "Notes" or "Excalidraw".',
    properties: {
      'name': {'type': 'string'},
    },
    required: ['name'],
  ),
  ToolSpec(
    'open_url',
    'Open a website in the default browser, like "excalidraw.com" or a full link.',
    properties: {
      'url': {'type': 'string'},
    },
    required: ['url'],
  ),
];

/// The system prompt that teaches a text LLM how to call the tools above.
String buildSystemPrompt() {
  final buffer = StringBuffer()
    ..writeln('You are Bluey, a little helper living on the user\'s Mac.')
    ..writeln(
      'You can see the screen, point at things, and use the computer when asked.',
    )
    ..writeln()
    ..writeln('To act, reply with exactly one JSON block on its own line:')
    ..writeln('{"tool": "<name>", "arguments": {...}}')
    ..writeln(
      'Any other text you write is spoken to the user. Keep it short and warm.',
    )
    ..writeln()
    ..writeln('Tools:');
  for (final tool in kTools) {
    buffer.writeln('- ${tool.name}: ${tool.description}');
    if (tool.properties.isNotEmpty) {
      final params = tool.properties.entries
          .map(
            (e) =>
                '${e.key}${tool.required.contains(e.key) ? ' (required)' : ''}',
          )
          .join(', ');
      buffer.writeln('  arguments: $params');
    }
  }
  return buffer.toString();
}
