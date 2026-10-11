import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_bluey/services/egress_monitor.dart';
import 'package:local_bluey/services/privacy_guard.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/ui/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

const remote = 'https://settings-fixture.invalid/v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in [
    'initial-refusal',
    'read-failure',
    'fresh-refusal',
    'success',
    'provider-error',
  ]) {
    testWidgets(
      'actual Settings $scenario actual record versus provider callback',
      (tester) async {
        late Directory telemetry;
        late Zone ioZone;
        await tester.runAsync(() async {
          ioZone = Zone.current;
          telemetry = await Directory.systemTemp.createTemp(
            'settings-egress-490-',
          );
        });
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
        const secureChannel = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        messenger.setMockMethodCallHandler(
          pathChannel,
          (_) async => telemetry.path,
        );
        messenger.setMockMethodCallHandler(secureChannel, (_) async => null);
        SharedPreferences.setMockInitialValues({
          'brain.baseUrl': remote,
          'brain.model': 'fixture-model',
        });
        final previousPrivacy = PrivacyGuard.debugPreferences;
        final previousOverride = PrivacyGuard.debugLocalOnlyOverride;
        final previousRecord = SettingsScreen.debugRecordTestEgress;
        final previousChat = SettingsScreen.debugTestChat;
        final previousRead = SettingsScreen.debugReadField;
        final previousWrite = SettingsScreen.debugWriteField;
        final previousWarning = SettingsStore.lastSecureStorageWarning;
        bool stored = scenario == 'initial-refusal', readFails = false;
        final owner = LocalOnlyPreferences(
          read: () async {
            if (readFails) throw StateError('synthetic read failure');
            return stored;
          },
          write: (value) async {
            stored = value;
            return true;
          },
          remove: () async {
            stored = false;
            return true;
          },
        );
        PrivacyGuard.debugPreferences = owner;
        PrivacyGuard.debugLocalOnlyOverride = null;
        SettingsScreen.debugReadField = null;
        SettingsScreen.debugWriteField = null;
        final recordEntered = Completer<void>(),
            recordRelease = Completer<void>();
        final recorded = Completer<void>(),
            afterRecordRelease = Completer<void>();
        final providerEntered = Completer<void>(),
            providerRelease = Completer<String>();
        var delegateCalls = 0, providerCalls = 0;
        String? recordedUrl, providerUrl;
        Future<void>? recording;
        SettingsScreen.debugRecordTestEgress = (url) async {
          recordedUrl = url;
          delegateCalls++;
          recordEntered.complete();
          await recordRelease.future;
          recording = ioZone.run(
            () => EgressMonitor.instance.record(url, 'settings-test', 0),
          );
          await recording;
          recorded.complete();
          await afterRecordRelease.future;
        };
        // Explicit forbidden-network delegate, never settings.buildProvider().
        SettingsScreen.debugTestChat = (settings) {
          providerUrl = settings.baseUrl;
          providerCalls++;
          providerEntered.complete();
          return providerRelease.future;
        };
        Future<void> rows(int count) async {
          await tester.runAsync(() async {
            await EgressMonitor.instance.load();
            expect(EgressMonitor.instance.entries, hasLength(count));
            if (count == 1) {
              final row = EgressMonitor.instance.entries.single;
              expect(row.host, 'settings-fixture.invalid');
              expect(row.kind, 'settings-test');
              expect(row.bytes, 0);
            }
          });
        }

        addTearDown(() async {
          if (!recordRelease.isCompleted) recordRelease.complete();
          if (!afterRecordRelease.isCompleted) afterRecordRelease.complete();
          if (!providerRelease.isCompleted) providerRelease.complete('cleanup');
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await EgressMonitor.instance.load();
            await EgressMonitor.instance.clear();
            expect(await telemetry.list().toList(), isEmpty);
            await telemetry.delete();
            expect(await telemetry.exists(), false);
          });
          SettingsScreen.debugRecordTestEgress = previousRecord;
          SettingsScreen.debugTestChat = previousChat;
          SettingsScreen.debugReadField = previousRead;
          SettingsScreen.debugWriteField = previousWrite;
          SettingsStore.lastSecureStorageWarning = previousWarning;
          PrivacyGuard.debugPreferences = previousPrivacy;
          PrivacyGuard.debugLocalOnlyOverride = previousOverride;
          owner.dispose();
          SharedPreferences.setMockInitialValues({});
          messenger.setMockMethodCallHandler(pathChannel, null);
          messenger.setMockMethodCallHandler(secureChannel, null);
          tester.view.reset();
        });
        await tester.runAsync(() => EgressMonitor.instance.clear());
        tester.view.physicalSize = const Size(1000, 5000);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('fixture-model'), findsOneWidget);
        expect(find.text(remote), findsOneWidget);
        final button = find.widgetWithText(OutlinedButton, 'Test connection');
        expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
        readFails = scenario == 'read-failure';
        tester.widget<OutlinedButton>(button).onPressed!();
        await tester.pumpAndSettle();
        if (scenario == 'initial-refusal' || scenario == 'read-failure') {
          await tester.pumpAndSettle();
          expect(delegateCalls, 0);
          expect(providerCalls, 0);
          await rows(0);
          expect(
            find.textContaining(
              scenario == 'read-failure'
                  ? 'Could not verify local-only mode'
                  : 'Blocked by Local-only mode',
            ),
            findsOneWidget,
          );
        } else {
          expect(recordEntered.isCompleted, true);
          expect(delegateCalls, 1);
          expect(recordedUrl, remote);
          await rows(0); // Callback entry alone is not a metadata record.
          recordRelease.complete();
          await tester.pump();
          await tester.runAsync(() => recording!);
          await tester.pump();
          expect(recorded.isCompleted, true);
          await rows(1);
          expect(providerCalls, 0);
          if (scenario == 'fresh-refusal') {
            await owner.set(true);
            afterRecordRelease.complete();
            await tester.pumpAndSettle();
            expect(providerCalls, 0);
            expect(
              find.textContaining('Blocked by Local-only mode'),
              findsOneWidget,
            );
          } else {
            afterRecordRelease.complete();
            await tester.pumpAndSettle();
            expect(providerEntered.isCompleted, true);
            expect(providerCalls, 1);
            expect(providerUrl, remote);
            await rows(1);
            if (scenario == 'provider-error') {
              providerRelease.completeError(
                StateError('synthetic provider failure'),
              );
            } else {
              providerRelease.complete('fixture answer');
            }
            await tester.pumpAndSettle();
            if (scenario == 'success') {
              expect(find.text('Connected: fixture answer'), findsOneWidget);
            }
          }
          await rows(
            1,
          ); // Attempt metadata survives refusal or callback failure.
        }
        expect(tester.takeException(), isNull);
        // Provider callback count is not actual transport, receipt or readiness.
      },
    );
  }
}
