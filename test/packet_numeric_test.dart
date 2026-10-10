import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/link/models.dart';
import 'package:local_bluey/link/line_connection.dart';

class Transport implements LineTransport {
  final inputController = StreamController<List<int>>();
  @override
  Stream<List<int>> get input => inputController.stream;
  @override
  void configure() {}
  @override
  void write(String line) {}
  @override
  Future<void> close() async {}
  @override
  void destroy() {}
}

void main() {
  for (final key in ['gazeX', 'gazeY', 'talk', 'volume']) {
    final lower = key.startsWith('gaze') ? -1 : 0;
    for (final value in [lower, 1, 0.5, null]) {
      test('$key boundary/interior/null $value compatible', () {
        final p = Packet.fromJson(
          key == 'volume'
              ? {key: value}
              : {
                  'face': {key: value},
                },
        );
        final actual = key == 'volume'
            ? p.volume
            : key == 'gazeX'
            ? p.face!.gazeX
            : key == 'gazeY'
            ? p.face!.gazeY
            : p.face!.talk;
        expect(actual, value ?? (key == 'volume' ? null : 0));
      });
    }
    for (final bad in [
      lower - 0.001,
      1.001,
      double.nan,
      double.infinity,
      double.negativeInfinity,
      '0',
      true,
      [],
      {},
      1e200,
    ]) {
      test('$key rejects entire packet $bad', () {
        final map = <String, dynamic>{key: bad};
        if (key != 'volume') {
          expect(() => FaceState.fromJson(map), throwsFormatException);
        }
        expect(
          () => Packet.fromJson({
            'text': 'valid-other-field',
            if (key == 'volume') key: bad else 'face': map,
          }),
          throwsFormatException,
        );
      });
    }
  }
  test(
    'missing/null/mood handling and Unicode optional roundtrip unchanged',
    () {
      final empty = FaceState.fromJson({});
      expect(empty.toJson(), {
        'gazeX': 0.0,
        'gazeY': 0.0,
        'talk': 0.0,
        'mood': 'listening',
      });
      expect(FaceState.fromJson({'mood': 'unknown'}).mood, Mood.listening);
      expect(FaceState.fromJson({'mood': 'happy'}).mood, Mood.happy);
      expect(Packet.fromJson({}).volume, isNull);
      expect(Packet.fromJson({'face': null}).face, isNull);
      final original = Packet(
        face: FaceState(gazeX: -1, gazeY: 1, talk: 0.5, mood: Mood.talking),
        volume: 1,
        hello: 'שלום',
        command: 'token',
        audio: 'YWJj',
        speech: 5,
        callID: 'id',
        tool: 'speak',
        text: 'שלום 🌟',
        image: 'aW1n',
      );
      expect(
        Packet.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
        ).toJson(),
        original.toJson(),
      );
    },
  );
  test('local mutable constructors and toJson not clamped', () {
    final face = FaceState(gazeX: 2, talk: -1)..gazeY = 3;
    final packet = Packet(face: face, volume: 2);
    expect(packet.toJson()['volume'], 2);
    expect(face.toJson()['gazeX'], 2);
    expect(face.toJson()['talk'], -1);
  });
  for (final key in ['gazeX', 'gazeY', 'talk', 'volume']) {
    test(
      'actual coalesced exponent overflow $key skips bad then delivers valid without done',
      () async {
        final t = Transport(), c = LineConnection.withTransport(Transport());
        await c.close();
        final actual = LineConnection.withTransport(t);
        var done = 0;
        final received = <Packet>[];
        actual.done.listen((_) => done++);
        final complete = Completer<void>();
        actual.packets.listen((p) {
          received.add(p);
          complete.complete();
        });
        actual.start();
        final field = key == 'volume'
            ? '"volume":1e400'
            : '"face":{"$key":1e400}';
        t.inputController.add(
          utf8.encode(
            '{"text":"bad",$field}\n{"text":"also bad","volume":2}\n{"text":"שלום","volume":0.5}\n',
          ),
        );
        await complete.future.timeout(const Duration(seconds: 2));
        expect(received, hasLength(1));
        expect(received.single.text, 'שלום');
        expect(received.single.volume, 0.5);
        expect(done, 0);
        expect(actual.isClosed, isFalse);
        await actual.close();
        await t.inputController.close();
      },
    );
  }
}
