import 'package:PiliPlus/common/widgets/occlusion_avoidance.dart';
import 'package:PiliPlus/common/widgets/sliver/sliver_pinned_header.dart';
import 'package:PiliPlus/utils/ios/reserved_regions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A column 364 wide at the right of a 951x669 window, as the video page has
/// on iPhone Duo's inner display, with the status bar over its top right.
const _window = Size(951, 669);
const _columnLeft = 587.0;

Widget _page({required Rect? statusBar, required Widget column}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: OcclusionScope(
      occlusion: statusBar,
      child: Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: _window.width - _columnLeft,
          height: _window.height,
          child: column,
        ),
      ),
    ),
  );
}

Widget _row(int index) => SizedBox(
  key: ValueKey('row$index'),
  height: 60,
  child: const SizedBox.expand(),
);

Widget _list({ScrollController? controller, int pinnedAfter = -1}) {
  return Column(
    children: [
      const AvoidOcclusion(
        child: SizedBox(key: ValueKey('bar'), height: 45, width: 364),
      ),
      Expanded(
        child: CustomScrollView(
          controller: controller,
          slivers: [
            if (pinnedAfter >= 0) ...[
              SliverList.builder(
                itemCount: pinnedAfter,
                itemBuilder: AvoidOcclusion.rows((_, i) => _row(i)),
              ),
              const SliverPinnedHeader(
                child: AvoidOcclusion(
                  pinned: true,
                  child: SizedBox(key: ValueKey('pinned'), height: 30),
                ),
              ),
            ],
            SliverList.builder(
              itemCount: 40,
              itemBuilder: AvoidOcclusion.rows(
                (_, i) => _row(i + (pinnedAfter < 0 ? 0 : pinnedAfter)),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

double _width(WidgetTester tester, String key) =>
    tester.getSize(find.byKey(ValueKey(key))).width;

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .views
            .first
          ..physicalSize = _window
          ..devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  // 84 wide, down to 190: the bar and the rows starting at 45 and 105 and 165.
  const statusBar = Rect.fromLTRB(867, 0, 951, 190);

  testWidgets('what the status bar covers at rest keeps clear of it', (
    tester,
  ) async {
    await tester.pumpWidget(_page(statusBar: statusBar, column: _list()));
    await tester.pumpAndSettle();

    expect(_width(tester, 'bar'), 280);
    expect(_width(tester, 'row0'), 280);
    expect(_width(tester, 'row1'), 280);
    expect(_width(tester, 'row2'), 280);
    expect(_width(tester, 'row3'), 364);
    expect(_width(tester, 'row4'), 364);
  });

  testWidgets('a gap at the end of a row of controls is as wide as what is '
      'covered of the row', (tester) async {
    Widget column(double top) => Column(
      children: [
        SizedBox(height: top),
        const Padding(
          padding: EdgeInsets.only(right: 2),
          child: Row(
            children: [
              Expanded(child: SizedBox(height: 45)),
              SizedBox(key: ValueKey('close'), width: 40, height: 40),
              OcclusionGap(),
            ],
          ),
        ),
      ],
    );

    await tester.pumpWidget(_page(statusBar: statusBar, column: column(0)));
    await tester.pumpAndSettle();
    expect(tester.getTopRight(find.byKey(const ValueKey('close'))).dx, 867);

    // Below the status bar the button stays at the edge.
    await tester.pumpWidget(_page(statusBar: statusBar, column: column(200)));
    await tester.pumpAndSettle();
    expect(tester.getTopRight(find.byKey(const ValueKey('close'))).dx, 949);
  });

  testWidgets('nothing changes without a status bar', (tester) async {
    await tester.pumpWidget(_page(statusBar: null, column: _list()));
    await tester.pumpAndSettle();

    expect(_width(tester, 'bar'), 364);
    expect(_width(tester, 'row0'), 364);
  });

  testWidgets('a row that only passes under the status bar keeps its width, '
      'and the first rows keep their inset when they come back', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _page(
        statusBar: statusBar,
        column: _list(controller: controller),
      ),
    );
    await tester.pumpAndSettle();

    controller.jumpTo(300);
    await tester.pumpAndSettle();
    // Row 5 is now at the top of the list, under the status bar.
    expect(tester.getTopLeft(find.byKey(const ValueKey('row5'))).dy, 45);
    expect(_width(tester, 'row5'), 364);

    controller.jumpTo(3000);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row0')), findsNothing);

    controller.jumpTo(0);
    // Already on the first frame, so the rows after them do not jump.
    await tester.pump();
    expect(_width(tester, 'row0'), 280);
    expect(_width(tester, 'row2'), 280);
    expect(_width(tester, 'row3'), 364);
  });

  testWidgets('follows the status bar as it grows and shrinks', (tester) async {
    await tester.pumpWidget(_page(statusBar: statusBar, column: _list()));
    await tester.pumpAndSettle();

    // Without a Dynamic Island it ends above the second row.
    await tester.pumpWidget(
      _page(
        statusBar: const Rect.fromLTRB(867, 0, 951, 100),
        column: _list(),
      ),
    );
    await tester.pumpAndSettle();
    expect(_width(tester, 'bar'), 280);
    expect(_width(tester, 'row0'), 280);
    expect(_width(tester, 'row1'), 364);
    expect(_width(tester, 'row2'), 364);

    await tester.pumpWidget(_page(statusBar: null, column: _list()));
    await tester.pumpAndSettle();
    expect(_width(tester, 'bar'), 364);
    expect(_width(tester, 'row0'), 364);
  });

  testWidgets('a header that rests below the status bar keeps clear of it, '
      'since the list pins it at the top', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _page(
        statusBar: statusBar,
        column: _list(controller: controller, pinnedAfter: 6),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('pinned'))).dy, 405);
    expect(_width(tester, 'pinned'), 280);

    controller.jumpTo(1000);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('pinned'))).dy, 45);
    expect(_width(tester, 'pinned'), 280);
  });

  testWidgets('a sheet is measured where it comes to rest', (tester) async {
    final frame = GlobalKey();
    Widget sheet(double heightFactor) => _page(
      statusBar: statusBar,
      column: Stack(
        key: frame,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRect(
              child: Align(
                alignment: Alignment.topLeft,
                heightFactor: heightFactor,
                child: OcclusionRestAnchor(
                  frame: () => frame.currentContext?.findRenderObject(),
                  child: const SizedBox(
                    height: 669,
                    child: Column(
                      children: [
                        AvoidOcclusion(
                          child: SizedBox(
                            key: ValueKey('title'),
                            height: 45,
                            width: 364,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Just opened: the title is drawn near the bottom of the column.
    await tester.pumpWidget(sheet(0.1));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('title'))).dy,
      greaterThan(600),
    );
    expect(_width(tester, 'title'), 280);
  });

  test('the status bar is the region at the top of the strip', () {
    final regions = ReservedRegions.decode([
      [867.0, 0.0, 951.0, 190.0],
      [867.0, 600.0, 951.0, 669.0],
      [400, 0, 500, 30],
    ]);
    expect(regions, hasLength(3));
    expect(
      statusBarInStrip(regions: regions, size: _window, stripWidth: 84),
      const Rect.fromLTRB(867, 0, 951, 190),
    );
    expect(
      statusBarInStrip(regions: regions, size: _window, stripWidth: 0),
      isNull,
    );
    expect(
      statusBarInStrip(regions: const [], size: _window, stripWidth: 84),
      isNull,
    );
  });
}
