import 'dart:async';

import 'package:local_bluey/services/conversation.dart';

class MemoryConversationStorage implements ConversationStorage {
  String? contents;
  bool failRead = false, failWrite = false, failDelete = false;
  Completer<void>? reading, writing;
  final readEntered = Completer<void>();
  final writeEntered = Completer<void>();
  @override
  Future<String?> read() async {
    if (!readEntered.isCompleted) readEntered.complete();
    await reading?.future;
    if (failRead) throw StateError('read');
    return contents;
  }

  @override
  Future<void> write(String value) async {
    if (!writeEntered.isCompleted) writeEntered.complete();
    await writing?.future;
    if (failWrite) throw StateError('write');
    contents = value;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('delete');
    contents = null;
  }
}
