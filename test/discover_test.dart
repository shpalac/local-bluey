import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/conversation.dart';
import 'package:local_bluey/services/discover.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/conversation_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConversationStore store;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = ConversationStore(storage: MemoryConversationStorage());
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

  test('#93: recents come from the local log; clearing clears them', () async {
    await store.add('user', 'what time is it');
    await store.add('bluey', 'three pm');
    expect(Discover.recentRequests(store: store), ['what time is it']);
    await store.clear();
    expect(Discover.recentRequests(store: store), isEmpty);
  });

  test('#93: search is offline over local items only', () async {
    await store.add('bluey', 'the recipe uses basil');
    expect(Discover.search('basil', store: store), ['the recipe uses basil']);
    expect(Discover.search('', store: store), isEmpty);
    expect(Discover.search('nope', store: store), isEmpty);
  });
}
