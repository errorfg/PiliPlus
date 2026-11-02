import 'dart:io';
import 'dart:ui' show Size;

import 'package:PiliPlus/pages/video/landscape_layout.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:PiliPlus/utils/storage_pref.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  group('the landscape layouts', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('piliplus-layout-test-');
      Hive.init(tempDir.path);
      GStorage.setting = await Hive.openBox('setting');
    });

    setUp(() => GStorage.setting.clear());

    tearDownAll(() async {
      await Hive.close();
      await tempDir.delete(recursive: true);
    });

    void setWindow(WidgetTester tester, double width, double height) {
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = Size(width, height) * 3;
      addTearDown(tester.view.reset);
    }

    testWidgets('follow the window until chosen, on any foldable', (
      tester,
    ) async {
      setWindow(tester, 466, 678);
      expect(Pref.horizontalScreen, isFalse);

      setWindow(tester, 951, 669);
      expect(Pref.horizontalScreen, isTrue);

      setWindow(tester, 669, 951);
      expect(Pref.horizontalScreen, isTrue);

      setWindow(tester, 466, 678);
      expect(Pref.horizontalScreen, isFalse);
      expect(
        GStorage.setting.containsKey(SettingBoxKey.horizontalScreen),
        isFalse,
      );
    });

    testWidgets('stay as chosen in the settings', (tester) async {
      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.horizontalScreen, true),
      );
      setWindow(tester, 466, 678);
      expect(Pref.horizontalScreen, isTrue);

      await tester.runAsync(
        () => GStorage.setting.put(SettingBoxKey.horizontalScreen, false),
      );
      setWindow(tester, 951, 669);
      expect(Pref.horizontalScreen, isFalse);
    });
  });

  test('over the strip, the player keeps its size and the column widens', () {
    const stripWidth = 84.0;

    final width = landscapeVideoWidth(951.0 - stripWidth, 669);

    expect(951.0 - stripWidth - width, 280);
    expect(951.0 - width, 364);
    // Room left below the player for what goes under it.
    expect(669 - width * 9 / 16, greaterThan(300));
  });

  group('the strip for vertical bars', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('is an inset on the right alone, on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(verticalBarStripWidth(const EdgeInsets.only(right: 84)), 84);
    });

    test('is not the inset an iPhone has on both sides in landscape', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(
        verticalBarStripWidth(const EdgeInsets.only(left: 62, right: 62)),
        0,
      );
    });

    test('stays clear where it is on the left, with the camera in it', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(verticalBarStripWidth(const EdgeInsets.only(left: 84)), 0);
    });

    test('is not a camera cutout on Android', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      expect(verticalBarStripWidth(const EdgeInsets.only(right: 40)), 0);
    });
  });

  test('a window with no inset keeps its proportions', () {
    expect(landscapeVideoWidth(1194, 834), closeTo(1194 * 0.7, 0.01));
  });
}
