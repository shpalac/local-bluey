import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:local_bluey/services/diagnostics.dart';
import 'package:local_bluey/services/settings_store.dart';
import 'package:local_bluey/services/strings.dart';
import 'package:local_bluey/ui/troubleshooting_screen.dart';
import 'package:local_bluey/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['DIAG_CAPTURE'] != null) {
      final glyphs = await File(
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
      ).readAsBytes();
      await (FontLoader(
        'Capture',
      )..addFont(Future.value(ByteData.sublistView(glyphs)))).load();
      final icons = await File(
        '/tmp/flutter-local/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    }
  });
  for (final rtl in [false, true]) {
    testWidgets('mocked probe title compact 200% ${rtl ? 'HE' : 'EN'}', (
      tester,
    ) async {
      Strings.uiLanguage = rtl ? UiLanguage.hebrew : UiLanguage.english;
      addTearDown(() => Strings.uiLanguage = UiLanguage.system);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final provider = await Diagnostics.providerReachable(
        settings: () async => const BrainSettings(
          backend: BrainBackend.openAiCompatible,
          baseUrl: 'http://localhost',
          model: 'm',
        ),
        localOnly: () async => true,
        client: MockClient((_) async => http.Response('', 200)),
      );
      final results = [
        provider,
        const CheckResult(
          id: 'pairing',
          titleEn: 'Phone pairing',
          titleHe: 'צימוד טלפון',
          status: CheckStatus.unknown,
        ),
      ];
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light().copyWith(
              textTheme: AppTheme.light().textTheme.apply(
                fontFamily: Platform.environment['DIAG_CAPTURE'] != null
                    ? 'Capture'
                    : 'Roboto',
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: Directionality(
                textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                child: child!,
              ),
            ),
            home: TroubleshootingScreen(runChecks: () async => results),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(rtl ? provider.titleHe : provider.titleEn),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      final root = Platform.environment['DIAG_CAPTURE'];
      if (root != null) {
        await tester.runAsync(() async {
          final image =
              await (key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$root/diag-${rtl ? 'he' : 'en'}-200.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
