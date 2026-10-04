import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/deep_links.dart';

void main() {
  test('#91: valid links parse', () {
    expect(DeepLinks.parse('localbluey://wake')?.action, 'wake');
    expect(DeepLinks.parse('localbluey://stop')?.action, 'stop');
    final ask = DeepLinks.parse('localbluey://ask?text=what%20time');
    expect(ask?.action, 'ask');
    expect(ask?.text, 'what time');
  });

  test('#91: wrong scheme or unknown action is rejected', () {
    expect(DeepLinks.parse('https://wake'), isNull);
    expect(DeepLinks.parse('localbluey://delete-everything'), isNull);
    expect(DeepLinks.parse('localbluey://ask'), isNull); // no text
    expect(DeepLinks.parse('not a url'), isNull);
  });

  test('#91: only silent-safe actions are allowed', () {
    expect(
      DeepLinks.allowedActions,
      containsAll({'ask', 'wake', 'sleep', 'stop', 'mute', 'status'}),
    );
    // No computer-control action exists in the deep-link set.
    expect(DeepLinks.allowedActions, isNot(contains('click')));
    expect(DeepLinks.allowedActions, isNot(contains('type')));
  });
}
