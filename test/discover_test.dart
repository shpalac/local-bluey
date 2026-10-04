import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/conversation.dart';
import 'package:local_bluey/services/discover.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ConversationStore.instance.entries.clear();
  });

  test('#93: notifications default to OFF per type', () async {
    expect(await NotificationPrefs.instance.enabled('routineFinished'), false);
    expect(await NotificationPrefs.instance.enabled('pairRequest'), false);
  });

  test('#93: suggestions need no screen contents', () {
    final s = Discover.suggestions(
      awake: false,
      routineCount: 0,
      recentCount: 0,
    );
    expect(s, isNotEmpty);
    expect(s.length, lessThanOrEqualTo(3));
  });

  test('#93: recents come from the local log; clearing clears them', () {
    ConversationStore.instance.entries
      ..add(ConversationEntry(role: 'user', text: 'what time is it'))
      ..add(ConversationEntry(role: 'bluey', text: 'three pm'));
    expect(Discover.recentRequests(), ['what time is it']);
    ConversationStore.instance.entries.clear();
    expect(Discover.recentRequests(), isEmpty);
  });

  test('#93: search is offline over local items only', () {
    ConversationStore.instance.entries.add(
      ConversationEntry(role: 'bluey', text: 'the recipe uses basil'),
    );
    expect(Discover.search('basil'), ['the recipe uses basil']);
    expect(Discover.search(''), isEmpty);
    expect(Discover.search('nope'), isEmpty);
  });
}
