import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/tutorial.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('without pointing the tutorial ends after the first answer', () async {
    final c = TutorialController();
    c.configure(askPrompt: 'hello, what can you do?', pointing: false);
    expect(c.steps, [TutorialStep.wake, TutorialStep.ask]);
    c.notifyAwake();
    expect(c.instruction, contains('hello, what can you do?'));
    c.notifyAnswer();
    await Future<void>.delayed(Duration.zero);
    expect(c.visible, isFalse);
    expect(await TutorialController.isDone(), isTrue);
  });

  test('with pointing the third step still gates on a real point', () {
    final c = TutorialController();
    c.configure(pointing: true);
    expect(c.steps.length, 3);
    c.notifyAwake();
    c.notifyAnswer();
    expect(c.step, TutorialStep.point);
    expect(c.visible, isTrue);
  });

  test('a point event is ignored when pointing is not offered', () {
    final c = TutorialController();
    c.configure(pointing: false);
    c.notifyPointed();
    expect(c.visible, isTrue);
  });
}
