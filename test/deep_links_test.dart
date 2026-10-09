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
  test('canonical actions reject all route/query ambiguity (#289)', () {
    for (final action in DeepLinks.allowedActions) {
      if (action != 'ask') {
        expect(DeepLinks.parse('localbluey://$action')?.action, action);
        expect(DeepLinks.parse('localbluey://$action?text=x'), isNull);
      }
    }
    for (final url in [
      'localbluey:///wake',
      'localbluey:wake',
      'localbluey://wake/',
      'localbluey://wake/stop',
      'localbluey://user@wake',
      'localbluey://wake:80',
      'localbluey://wake#fragment',
      'localbluey://wake?',
      'localbluey://wake?unknown=x',
      'localbluey://ask?text=a&text=b',
      'localbluey://ask?text=a&other=b',
      'localbluey://ask?other=a',
      'localbluey://ask?%74ext=a',
      'localbluey://ask?text=a=b',
      'localbluey://ask?text=a#x',
      'LOCALBLUEY://wake',
      'localbluey://WAKE',
      'localbluey://wake\n',
    ]) {
      expect(DeepLinks.parse(url), isNull, reason: url);
    }
  });

  test('encoded asks retain original Hebrew/English/emoji and spaces', () {
    for (final text in ['what time', 'שלום 😀', '  hello  ', 'a&b=c#d', '+']) {
      expect(
        DeepLinks.parse(
          'localbluey://ask?text=${Uri.encodeQueryComponent(text)}',
        )?.text,
        text,
      );
    }
    expect(
      DeepLinks.parse('localbluey://ask?text=hello+world')?.text,
      'hello world',
    );
  });

  test('empty/whitespace and malformed percent or UTF-8 reject safely', () {
    for (final text in [
      '',
      '%20%09',
      '%',
      '%2',
      '%GG',
      '%FF',
      '%C3%28',
      'literal space',
      'שלום',
    ]) {
      expect(
        () => DeepLinks.parse('localbluey://ask?text=$text'),
        returnsNormally,
      );
      expect(
        DeepLinks.parse('localbluey://ask?text=$text'),
        isNull,
        reason: text,
      );
    }
  });

  test('decoded UTF-8 and encoded input size limits are enforced', () {
    final exact = 'a' * DeepLinks.maxAskBytes;
    expect(DeepLinks.parse('localbluey://ask?text=$exact')?.text, exact);
    expect(DeepLinks.parse('localbluey://ask?text=${exact}a'), isNull);
    final emoji = '😀' * (DeepLinks.maxAskBytes ~/ 4);
    expect(
      DeepLinks.parse(
        'localbluey://ask?text=${Uri.encodeQueryComponent(emoji)}',
      )?.text,
      emoji,
    );
    expect(
      DeepLinks.parse(
        'localbluey://ask?text=${Uri.encodeQueryComponent('${emoji}a')}',
      ),
      isNull,
    );
    expect(
      DeepLinks.parse(
        'localbluey://ask?text=${'a' * DeepLinks.maxInputLength}',
      ),
      isNull,
    );
  });
}
