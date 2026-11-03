import 'package:PiliPlus/pages/main/iphone_duo_layout.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// The window and insets iOS 27.1 gives an app in a pose of the device.
class _Pose {
  const _Pose(this.size, this.viewPadding);

  final Size size;
  final EdgeInsets viewPadding;
}

const _innerFlat = _Pose(Size(951, 669), EdgeInsets.only(right: 84));
const _outer = _Pose(Size(466, 678), EdgeInsets.only(right: 84));
const _upright = _Pose(Size(669, 951), EdgeInsets.only(top: 82, bottom: 34));
const _outerRight = _Pose(Size(678, 466), EdgeInsets.only(right: 84));
const _outerLeft = _Pose(Size(678, 466), EdgeInsets.only(left: 84));

const _bodyKey = ValueKey('body');
const _actionKey = ValueKey('action');
final _bar = find.byKey(const ValueKey('iPhoneDuoBar'));
final _firstTab = find.byKey(const ValueKey('iPhoneDuoTab0'));
final _lastTab = find.byKey(const ValueKey('iPhoneDuoTab2'));

void main() {
  final nativeViews = <String>[];
  final nativeParams = <Map>[];
  final selected = <int>[];

  setUp(() {
    nativeViews.clear();
    nativeParams.clear();
    selected.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
          if (call.method == 'create') {
            nativeViews.add((call.arguments as Map)['viewType'] as String);
            nativeParams.add(
              const StandardMessageCodec().decodeMessage(
                    ByteData.sublistView(
                      (call.arguments as Map)['params'] as Uint8List,
                    ),
                  )
                  as Map,
            );
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform_views, null);
  });

  Future<void> pump(
    WidgetTester tester,
    _Pose pose, {
    bool withActions = false,
    int tabs = 3,
  }) async {
    FakeViewPadding fake(EdgeInsets padding) => FakeViewPadding(
      left: padding.left * 3,
      top: padding.top * 3,
      right: padding.right * 3,
      bottom: padding.bottom * 3,
    );

    tester.view
      ..devicePixelRatio = 3
      ..physicalSize = pose.size * 3
      ..padding = fake(pose.viewPadding)
      ..viewPadding = fake(pose.viewPadding);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: IPhoneDuoLayout(
            selectedIndex: 0,
            onDestinationSelected: selected.add,
            destinations: List.filled(
              tabs,
              const IPhoneDuoDestination(
                label: 'tab',
                icon: Icon(Icons.star_border),
                selectedIcon: Icon(Icons.star),
              ),
            ),
            actions: [
              if (withActions) const SizedBox.square(key: _actionKey, dimension: 34),
              if (withActions) const SizedBox.square(dimension: 34),
              if (withActions) const SizedBox.square(dimension: 34),
            ],
            body: const SizedBox.expand(key: _bodyKey),
          ),
        ),
      ),
    );
  }

  Rect body(WidgetTester tester) => tester.getRect(find.byKey(_bodyKey));

  group('along the right edge', () {
    testWidgets('inner display, open flat', (tester) async {
      await pump(tester, _innerFlat, withActions: true);

      final bar = tester.getRect(_bar);
      expect(bar.right, 951);
      expect(bar.width, 84);
      expect(body(tester).right, bar.left);

      // Under the status bar, in the system's column; the tabs at the bottom.
      expect(tester.getRect(find.byKey(_actionKey)).center.dx, 951 - 48);
      expect(tester.getRect(find.byKey(_actionKey)).top, greaterThan(120));
      expect(tester.getRect(_firstTab).center.dx, 951 - 48);
      expect(tester.getRect(_lastTab).bottom, lessThanOrEqualTo(669 - 24 - 6));
      expect(
        tester.getRect(_firstTab).top,
        greaterThan(tester.getRect(find.byKey(_actionKey)).bottom),
      );
    });

    testWidgets('outer display, below the camera', (tester) async {
      await pump(tester, _outer, withActions: true);

      expect(tester.getRect(_bar).right, 466);
      expect(tester.getRect(find.byKey(_actionKey)).top, greaterThan(170));
      expect(tester.getRect(_lastTab).bottom, lessThanOrEqualTo(678 - 24 - 6));
    });

    testWidgets('outer display on its side, above the camera', (tester) async {
      await pump(tester, _outerRight, withActions: true);

      expect(tester.getRect(_bar).right, 678);
      expect(tester.getRect(find.byKey(_actionKey)).top, greaterThan(24));
      expect(tester.getRect(find.byKey(_actionKey)).top, lessThan(40));
      expect(tester.getRect(_lastTab).bottom, lessThanOrEqualTo(466 - 82 - 6));
    });

    testWidgets('still on the right where the system chose the left', (
      tester,
    ) async {
      await pump(tester, _outerLeft, withActions: true);

      expect(tester.getRect(_bar).right, 678);
      expect(body(tester).left, 84);
      expect(tester.getRect(_lastTab).bottom, lessThanOrEqualTo(466 - 24 - 6));
    });
  });

  testWidgets('held upright: beside the status bar, above the page', (
    tester,
  ) async {
    await pump(tester, _upright);

    final first = tester.getRect(_firstTab);
    final last = tester.getRect(_lastTab);
    expect(first.left, greaterThanOrEqualTo(20));
    expect(first.center.dy, 48);
    expect(last.center.dy, 48);
    expect(last.right, lessThanOrEqualTo(669 - 134));

    // The page keeps its whole width and the inset.
    expect(body(tester).top, 82);
    expect(body(tester).width, 669);
  });

  testWidgets('the capsules are iOS\'s own glass', (tester) async {
    await pump(tester, _innerFlat, withActions: true);

    expect(nativeViews, ['piliplus/native_glass', 'piliplus/native_glass']);
  });

  testWidgets('the native view takes in what the glass draws past its bounds', (
    tester,
  ) async {
    await pump(tester, _innerFlat);

    // What is above a platform view covers it only as far as the view's frame.
    final view = tester.getRect(find.byType(UiKitView));
    const margin = 24.0;
    expect(view.width, 48 + margin * 2);
    expect(view.center.dx, 951 - 48);
    expect(view.height, 3 * 50 + 12 + margin * 2);
    expect(nativeParams.single['margin'], margin);
  });

  testWidgets('a tab selects its destination', (tester) async {
    await pump(tester, _innerFlat);

    await tester.tap(_lastTab);

    expect(selected, [2]);
  });

  testWidgets('one destination needs no tabs', (tester) async {
    await pump(tester, _innerFlat, tabs: 1);

    expect(_firstTab, findsNothing);
    expect(nativeViews, isEmpty);
  });
}
