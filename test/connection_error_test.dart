import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/llm/ollama_provider.dart' show LlmException;
import 'package:local_bluey/services/connection_error.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const local = 'http://localhost:8080/v1';

  group('connectionTarget (#239)', () {
    test('uses the URL port, not any client port', () {
      expect(connectionTarget(local), 'localhost:8080');
    });
    test('falls back to the scheme default port', () {
      expect(
        connectionTarget('https://api.example.com/v1'),
        'api.example.com:443',
      );
      expect(connectionTarget('http://example.com'), 'example.com:80');
    });
    test('returns raw text for an unparseable URL', () {
      expect(connectionTarget('not a url'), 'not a url');
    });
  });

  group('describeConnectionFailure (#239)', () {
    test('refused names the configured port and a next step', () {
      final f = describeConnectionFailure(
        Exception(
          'ClientException with SocketException: Connection refused '
          '(OS Error: Connection refused, errno = 61), address = localhost, '
          'port = 51229, uri=http://localhost:8080/v1/chat/completions',
        ),
        local,
      );
      expect(f.kind, ConnectionFailureKind.refused);
      expect(f.summary, contains('localhost:8080'));
      expect(f.summary, contains('ollama serve'));
      expect(f.summary, isNot(contains('51229')));
      expect(f.summary, isNot(contains('SocketException')));
      expect(f.summary, isNot(contains('errno')));
      expect(f.details, contains('errno = 61'));
      expect(f.suggestsLocalServer, isTrue);
    });

    test('refused on a remote host does not suggest ollama serve', () {
      final f = describeConnectionFailure(
        Exception('Connection refused, errno = 111'),
        'https://api.example.com/v1',
      );
      expect(f.kind, ConnectionFailureKind.refused);
      expect(f.summary, contains('api.example.com:443'));
      expect(f.summary, isNot(contains('ollama serve')));
    });

    test('timeout', () {
      final f = describeConnectionFailure(TimeoutException('slow'), local);
      expect(f.kind, ConnectionFailureKind.timeout);
      expect(f.summary, contains('localhost:8080'));
    });

    test('unknown host', () {
      final f = describeConnectionFailure(
        Exception('SocketException: Failed host lookup: nope.invalid'),
        'https://nope.invalid/v1',
      );
      expect(f.kind, ConnectionFailureKind.unreachableHost);
    });

    test('tls', () {
      final f = describeConnectionFailure(
        Exception('HandshakeException: CERTIFICATE_VERIFY_FAILED'),
        'https://example.com/v1',
      );
      expect(f.kind, ConnectionFailureKind.tls);
    });

    test('401 and 403 mean a bad key', () {
      for (final code in [401, 403]) {
        final f = describeConnectionFailure(
          LlmException('OpenAI-compatible $code: {"error":"nope"}'),
          local,
        );
        expect(f.kind, ConnectionFailureKind.unauthorized);
        expect(f.summary, contains('$code'));
      }
    });

    test('404 about a model means the model is missing', () {
      final f = describeConnectionFailure(
        LlmException('Ollama 404: {"error":"model \'x\' not found"}'),
        'http://localhost:11434',
      );
      expect(f.kind, ConnectionFailureKind.modelMissing);
    });

    test('plain 404 means a wrong path', () {
      final f = describeConnectionFailure(
        LlmException('OpenAI-compatible 404: Not Found'),
        local,
      );
      expect(f.kind, ConnectionFailureKind.wrongPath);
      expect(f.summary, contains('/v1'));
    });

    test('other status and unknown errors keep the raw text in details', () {
      final a = describeConnectionFailure(
        LlmException('OpenAI-compatible 500: boom'),
        local,
      );
      expect(a.kind, ConnectionFailureKind.other);
      expect(a.details, contains('500'));
      final b = describeConnectionFailure(Exception('weird'), local);
      expect(b.kind, ConnectionFailureKind.other);
      expect(b.details, contains('weird'));
    });
  });

  group('settings Test connection with nothing listening (#239)', () {
    testWidgets('shows a friendly message, the Detect action and Details', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SettingsScreen.debugTestChat = (_) async => throw Exception(
        'ClientException with SocketException: Connection refused '
        '(OS Error: Connection refused, errno = 61), port = 51229',
      );
      addTearDown(() => SettingsScreen.debugTestChat = null);
      await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Base URL'),
        'http://127.0.0.1:1',
      );
      final test = find.text('Test connection');
      await tester.scrollUntilVisible(
        test,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(test);
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(
        find.textContaining('Nothing is listening at 127.0.0.1:1'),
        findsOneWidget,
      );
      expect(find.textContaining('SocketException'), findsNothing);
      expect(
        find.text('Detect local Ollama', skipOffstage: false),
        findsWidgets,
      );
      expect(find.text('Details', skipOffstage: false), findsOneWidget);
    });
  });
}
