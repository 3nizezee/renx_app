// Node types for the subset of the Ren'Py script language that the built-in
// interpreter understands. Both the .rpy text parser and the .rpyc decoder
// produce these nodes, so the runtime only has to deal with one shape.
//
// This file must stay free of Flutter imports so it can be unit tested with
// the plain Dart SDK and passed between isolates.

/// A list of statements. Every block gets a stable numeric id after loading so
/// that execution positions can be written into save files.
class ScriptBlock {
  ScriptBlock(this.nodes);

  final List<ScriptNode> nodes;
  int id = -1;
}

abstract class ScriptNode {
  ScriptNode(this.file, this.line);

  final String file;
  final int line;

  /// Short human readable description used in diagnostics.
  String describe();
}

/// Image reference used by scene, show and hide.
class ImageSpec {
  ImageSpec({
    required this.name,
    this.expression,
    this.tag,
    this.atList = const <String>[],
    this.layer,
  });

  /// Image name components, for example ['eileen', 'happy'].
  final List<String> name;

  /// Source of a `show expression ...` displayable expression.
  final String? expression;

  /// Explicit `as` tag.
  final String? tag;

  /// Transform names from the `at` clause, for example ['left'].
  final List<String> atList;

  final String? layer;

  String get effectiveTag {
    if (tag != null && tag!.isNotEmpty) return tag!;
    if (name.isNotEmpty) return name.first;
    return expression ?? '';
  }

  @override
  String toString() =>
      expression != null ? 'expression $expression' : name.join(' ');
}

class LabelNode extends ScriptNode {
  LabelNode(super.file, super.line,
      {required this.name, required this.block, this.parameters});

  final String name;
  final ScriptBlock block;
  final String? parameters;

  @override
  String describe() => 'label $name';
}

class SayNode extends ScriptNode {
  SayNode(
    super.file,
    super.line, {
    required this.who,
    required this.what,
    this.attributes = const <String>[],
    this.temporaryAttributes = const <String>[],
    this.interact = true,
    this.transition,
  });

  /// Speaker expression source: a variable name such as `e`, a string literal
  /// such as `"Eileen"`, or null for the narrator.
  final String? who;
  final String what;
  final List<String> attributes;
  final List<String> temporaryAttributes;

  /// False for a say statement that only acts as a menu caption.
  final bool interact;
  final String? transition;

  @override
  String describe() => 'say ${who ?? 'narrator'}';
}

class MenuChoice {
  MenuChoice({required this.text, required this.block, this.condition});

  final String text;
  final String? condition;
  final ScriptBlock block;
}

class MenuNode extends ScriptNode {
  MenuNode(super.file, super.line,
      {required this.choices, this.caption, this.setVariable});

  final List<MenuChoice> choices;

  /// Plain caption item (a string without a block inside the menu).
  final String? caption;
  final String? setVariable;

  @override
  String describe() => 'menu (${choices.length} choices)';
}

class JumpNode extends ScriptNode {
  JumpNode(super.file, super.line,
      {required this.target, this.isExpression = false});

  final String target;
  final bool isExpression;

  @override
  String describe() => 'jump $target';
}

class CallNode extends ScriptNode {
  CallNode(super.file, super.line,
      {required this.target, this.isExpression = false});

  final String target;
  final bool isExpression;

  @override
  String describe() => 'call $target';
}

class ReturnNode extends ScriptNode {
  ReturnNode(super.file, super.line);

  @override
  String describe() => 'return';
}

class IfBranch {
  IfBranch({required this.condition, required this.block});

  /// Null means `else`.
  final String? condition;
  final ScriptBlock block;
}

class IfNode extends ScriptNode {
  IfNode(super.file, super.line, {required this.branches});

  final List<IfBranch> branches;

  @override
  String describe() => 'if';
}

class WhileNode extends ScriptNode {
  WhileNode(super.file, super.line,
      {required this.condition, required this.block});

  final String condition;
  final ScriptBlock block;

  @override
  String describe() => 'while $condition';
}

class SceneNode extends ScriptNode {
  SceneNode(super.file, super.line, {this.image, this.transition});

  final ImageSpec? image;
  final String? transition;

  @override
  String describe() => 'scene ${image ?? ''}';
}

class ShowNode extends ScriptNode {
  ShowNode(super.file, super.line, {required this.image, this.transition});

  final ImageSpec image;
  final String? transition;

  @override
  String describe() => 'show $image';
}

class HideNode extends ScriptNode {
  HideNode(super.file, super.line, {required this.image, this.transition});

  final ImageSpec image;
  final String? transition;

  @override
  String describe() => 'hide $image';
}

class WithNode extends ScriptNode {
  WithNode(super.file, super.line, {required this.transition});

  final String transition;

  @override
  String describe() => 'with $transition';
}

class PythonNode extends ScriptNode {
  PythonNode(super.file, super.line, {required this.source});

  final String source;

  @override
  String describe() => 'python';
}

class DefineNode extends ScriptNode {
  DefineNode(super.file, super.line,
      {required this.name, required this.expression, this.operator = '='});

  /// Fully qualified name without the leading `store.`, for example
  /// `e`, `config.name` or `audio.theme`.
  final String name;
  final String expression;
  final String operator;

  @override
  String describe() => 'define $name';
}

class DefaultNode extends ScriptNode {
  DefaultNode(super.file, super.line,
      {required this.name, required this.expression});

  final String name;
  final String expression;

  @override
  String describe() => 'default $name';
}

class ImageNode extends ScriptNode {
  ImageNode(super.file, super.line, {required this.name, this.expression});

  final List<String> name;

  /// Expression producing the displayable, or null when it could not be
  /// determined (for example a complex ATL block).
  final String? expression;

  @override
  String describe() => 'image ${name.join(' ')}';
}

class InitNode extends ScriptNode {
  InitNode(super.file, super.line,
      {required this.priority, required this.block});

  final int priority;
  final ScriptBlock block;

  @override
  String describe() => 'init $priority';
}

class PauseNode extends ScriptNode {
  PauseNode(super.file, super.line, {this.duration});

  final String? duration;

  @override
  String describe() => 'pause ${duration ?? ''}';
}

class PlayNode extends ScriptNode {
  PlayNode(super.file, super.line,
      {required this.channel,
      required this.fileExpression,
      this.loop,
      this.queue = false});

  final String channel;
  final String fileExpression;

  /// Null means use the channel default (music loops, sound does not).
  final bool? loop;
  final bool queue;

  @override
  String describe() => 'play $channel';
}

class StopNode extends ScriptNode {
  StopNode(super.file, super.line, {required this.channel});

  final String channel;

  @override
  String describe() => 'stop $channel';
}

/// A statement that was recognised but is not supported (screens, ATL,
/// custom user statements). It is skipped at runtime and reported in the
/// compatibility report.
class UnsupportedNode extends ScriptNode {
  UnsupportedNode(super.file, super.line, {required this.description});

  final String description;

  @override
  String describe() => description;
}

/// One script file after parsing or decoding.
class ScriptFile {
  ScriptFile({required this.path, required this.block, required this.origin});

  /// Path relative to the game directory, using forward slashes.
  final String path;
  final ScriptBlock block;

  /// 'rpy', 'rpyc', 'rpy (archive)' or 'rpyc (archive)'.
  final String origin;
}
