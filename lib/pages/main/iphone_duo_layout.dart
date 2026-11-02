import 'package:PiliPlus/common/widgets/native_glass.dart';
import 'package:material_ui/material_ui.dart';

class IPhoneDuoDestination {
  const IPhoneDuoDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final Widget icon;
  final Widget selectedIcon;
}

/// The main page on iPhone Duo. Navigation goes where the system puts its own
/// bars, on glass: along the right edge in every pose but one, and beside the
/// status bar at the top of the inner display held upright.
///
/// The numbers are those of the system's bars, measured on the iOS 27.1
/// simulator: a column 48 wide in a strip 84 wide, 12 from the content.
class IPhoneDuoLayout extends StatelessWidget {
  const IPhoneDuoLayout({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.actions,
    required this.body,
  });

  final List<IPhoneDuoDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Controls for the pages with no row of their own to hold them.
  final List<Widget> actions;
  final Widget body;

  static const double _controlExtent = 48;
  static const double _itemExtent = 50;
  static const double _capsuleInset = 6;
  static const double _inset = 12;
  static const double _edgeMargin = 24;

  /// What the status bar takes of the top right corner when held upright, and
  /// the gap to it.
  static const double _statusCornerWidth = 134;
  static const double _statusCornerGap = 2;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    // iOS reports the strip as an inset on one side only.
    return (padding.left > 0) != (padding.right > 0)
        ? _buildWithStrip(context, padding)
        : _buildWithTopRow(context, padding);
  }

  /// On the right whichever edge the system chose. Where it chose the left, its
  /// status bar and camera are over there, with nothing to avoid on the right.
  Widget _buildWithStrip(BuildContext context, EdgeInsets padding) {
    final size = MediaQuery.sizeOf(context);
    final systemStripOnRight = padding.right > 0;
    final width = systemStripOnRight ? padding.right : padding.left;
    final outerDisplay = size.shortestSide < 600;
    final outerLandscape = outerDisplay && size.width > size.height;

    var top = padding.top + _edgeMargin;
    var bottom = _edgeMargin;
    if (systemStripOnRight && padding.top == 0) {
      if (outerLandscape) {
        // The status bar is hidden, and the camera at the bottom of the strip.
        bottom = 82;
      } else {
        top = outerDisplay ? 170 : 120;
      }
    }

    return Row(
      children: [
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeRight: true,
            child: Padding(
              padding: .only(left: padding.left, top: padding.top),
              child: body,
            ),
          ),
        ),
        SizedBox(
          key: const ValueKey('iPhoneDuoBar'),
          width: width,
          child: Padding(
            padding: .only(
              left: _inset,
              top: top,
              right: width - _controlExtent - _inset,
              bottom: bottom,
            ),
            child: Column(
              children: [
                if (actions.isNotEmpty) _buildCapsule(.vertical, actions),
                const Spacer(),
                if (destinations.length > 1) _buildTabs(context, .vertical),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The inner display held upright keeps the page's top inset clear for the
  /// status bar, which takes only the corner of it: the bar goes beside that.
  Widget _buildWithTopRow(BuildContext context, EdgeInsets padding) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(padding: padding.copyWith(bottom: 0), child: body),
        ),
        Positioned(
          key: const ValueKey('iPhoneDuoBar'),
          left: 20,
          top: _edgeMargin,
          right: _statusCornerWidth + _statusCornerGap,
          height: _controlExtent,
          child: Row(
            children: [
              if (actions.isNotEmpty) ...[
                _buildCapsule(.horizontal, actions),
                const SizedBox(width: _inset),
              ],
              if (destinations.length > 1) _buildTabs(context, .horizontal),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabs(BuildContext context, Axis axis) {
    return _buildCapsule(
      axis,
      List.generate(destinations.length, (index) {
        final destination = destinations[index];
        final selected = index == selectedIndex;
        final colorScheme = ColorScheme.of(context);
        return IconButton(
          key: ValueKey('iPhoneDuoTab$index'),
          tooltip: destination.label,
          color: selected ? colorScheme.primary : colorScheme.onSurface,
          style: selected
              ? IconButton.styleFrom(
                  backgroundColor: colorScheme.onSurface.withValues(alpha: 0.1),
                )
              : null,
          onPressed: () => onDestinationSelected(index),
          icon: selected ? destination.selectedIcon : destination.icon,
        );
      }),
    );
  }

  Widget _buildCapsule(Axis axis, List<Widget> children) {
    final length = children.length * _itemExtent + _capsuleInset * 2;
    final vertical = axis == .vertical;
    return SizedBox(
      width: vertical ? _controlExtent : length,
      height: vertical ? length : _controlExtent,
      child: Stack(
        children: [
          const Positioned.fill(child: NativeGlass()),
          Material(
            type: .transparency,
            child: Padding(
              padding: vertical
                  ? const .symmetric(vertical: _capsuleInset)
                  : const .symmetric(horizontal: _capsuleInset),
              child: Flex(
                direction: axis,
                children: [
                  for (final child in children)
                    SizedBox(
                      width: vertical ? null : _itemExtent,
                      height: vertical ? _itemExtent : null,
                      child: Center(child: child),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
