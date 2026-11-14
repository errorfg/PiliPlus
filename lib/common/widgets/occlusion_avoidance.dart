import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Tells the [AvoidOcclusion]s below which part of it something drawn over the
/// app covers, such as the status bar of iPhone Duo's vertical bar strip.
class OcclusionScope extends StatefulWidget {
  const OcclusionScope({
    super.key,
    required this.occlusion,
    required this.child,
  });

  /// The covered part, in the coordinates of [child]; null for none.
  final Rect? occlusion;

  final Widget child;

  @override
  State<OcclusionScope> createState() => OcclusionScopeState();
}

class OcclusionScopeState extends State<OcclusionScope> {
  final _boxes = <RenderAvoidOcclusion>{};
  bool _checkScheduled = false;

  /// The scopes with something to avoid. Their boxes are checked after every
  /// frame: a box moves when anything before it changes its size, without being
  /// laid out again itself.
  static final _active = <OcclusionScopeState>{};
  static bool _following = false;

  void _follow() {
    if (widget.occlusion == null) {
      _active.remove(this);
      return;
    }
    _active.add(this);
    if (_following) return;
    _following = true;
    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      for (final scope in _active) {
        scope.scheduleCheck();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(OcclusionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.occlusion != widget.occlusion) {
      _follow();
      scheduleCheck();
    }
  }

  @override
  void dispose() {
    _active.remove(this);
    super.dispose();
  }

  void _check() {
    for (final box in _boxes.toList()) {
      box.check();
    }
  }

  /// Checks every box once this frame is laid out.
  void scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (mounted) _check();
    });
  }

  bool get hasOcclusion => widget.occlusion != null;

  /// How far [box] has to keep from its right edge.
  double endInsetOf(RenderAvoidOcclusion box) {
    final occlusion = widget.occlusion;
    final scope = context.findRenderObject();
    if (occlusion == null || scope == null) return 0;

    final measured = box.measured;
    if (measured == null || !measured.hasSize) return 0;

    double inset(Offset? offset) {
      if (offset == null) return 0;
      final rect = offset & measured.size;
      return rect.top < occlusion.bottom &&
              rect.bottom > occlusion.top &&
              rect.left < occlusion.left &&
              rect.right > occlusion.left
          ? rect.right - occlusion.left
          : 0;
    }

    final atRest = inset(restOffset(measured, scope));
    return box.pinned
        ? math.max(atRest, inset(restOffset(measured, scope, pinned: true)))
        : atRest;
  }

  @override
  Widget build(BuildContext context) =>
      _OcclusionScopeData(state: this, child: widget.child);
}

class _OcclusionScopeData extends InheritedWidget {
  const _OcclusionScopeData({required this.state, required super.child});

  final OcclusionScopeState state;

  @override
  bool updateShouldNotify(_OcclusionScopeData oldWidget) =>
      state != oldWidget.state;
}

/// Keeps [child] clear of what the nearest [OcclusionScope] says is covered,
/// by leaving the covered width empty at its right.
///
/// Only where [child] is covered with every list around it scrolled to the
/// start: a row pinned under the status bar, or the first rows of a list. What
/// passes under the status bar only on its way up is left alone, since
/// scrolling back brings it out again.
class AvoidOcclusion extends SingleChildRenderObjectWidget {
  const AvoidOcclusion({
    super.key,
    this.pinned = false,
    this.slot,
    required Widget super.child,
  });

  /// Whether [child] is a header its list keeps at the top once scrolled. It
  /// then keeps clear of what covers it up there as well.
  final bool pinned;

  /// Tells apart the boxes in one row of a list, where a row has several.
  final Object? slot;

  /// Wraps the rows [builder] makes for a list.
  static NullableIndexedWidgetBuilder rows(
    NullableIndexedWidgetBuilder builder,
  ) => (context, index) {
    final child = builder(context, index);
    return child == null ? null : AvoidOcclusion(child: child);
  };

  /// Wraps each of the [children] of a list.
  static List<Widget> all(List<Widget> children) => [
    for (final child in children) AvoidOcclusion(child: child),
  ];

  @override
  RenderAvoidOcclusion createRenderObject(BuildContext context) =>
      RenderAvoidOcclusion(scope: _scopeOf(context), pinned: pinned)
        ..slot = slot;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAvoidOcclusion renderObject,
  ) {
    renderObject
      ..scope = _scopeOf(context)
      ..pinned = pinned
      ..slot = slot;
  }

  static OcclusionScopeState? _scopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OcclusionScopeData>()?.state;
}

/// An empty box as wide as what the nearest [OcclusionScope] says is covered of
/// the row it is in, to put at the end of a row of controls: a title on the
/// left and a close button on the right. See [AvoidOcclusion].
class OcclusionGap extends LeafRenderObjectWidget {
  const OcclusionGap({super.key, this.pinned = false});

  /// Whether the row is in a header its list keeps at the top once scrolled.
  final bool pinned;

  @override
  RenderAvoidOcclusion createRenderObject(BuildContext context) =>
      RenderAvoidOcclusion(
        scope: AvoidOcclusion._scopeOf(context),
        pinned: pinned,
        gap: true,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAvoidOcclusion renderObject,
  ) {
    renderObject
      ..scope = AvoidOcclusion._scopeOf(context)
      ..pinned = pinned;
  }
}

class RenderAvoidOcclusion extends RenderShiftedBox {
  RenderAvoidOcclusion({
    this._scope,
    this._pinned = false,
    this.gap = false,
    RenderBox? child,
  }) : super(child);

  /// Whether this is the gap at the end of a row, which then is the box to
  /// keep clear.
  final bool gap;

  /// The box whose covered width this leaves empty.
  RenderBox? get measured {
    if (!gap) return this;
    final parent = this.parent;
    return parent is RenderBox ? parent : null;
  }

  bool get pinned => _pinned;
  bool _pinned;
  set pinned(bool value) {
    if (_pinned == value) return;
    _pinned = value;
    markNeedsLayout();
  }

  /// Insets of the rows of a list by index, for the rows it drops and builds
  /// again: a row that came back without its inset would be measured too short
  /// and push the rows after it down a frame later.
  static final _rowInsets = Expando<Map<(int, Object?), double>>();

  /// See [AvoidOcclusion.slot].
  Object? slot;

  OcclusionScopeState? _scope;
  set scope(OcclusionScopeState? value) {
    if (_scope == value) return;
    if (attached) {
      _scope?._boxes.remove(this);
      value?._boxes.add(this);
    }
    _scope = value;
    markNeedsLayout();
  }

  /// Null until the first layout.
  double? _end;

  @visibleForTesting
  double get endInset => _end ?? 0;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scope?._boxes.add(this);
  }

  @override
  void detach() {
    _scope?._boxes.remove(this);
    super.detach();
  }

  (RenderSliverMultiBoxAdaptor, (int, Object?))? get _row {
    RenderObject node = this;
    for (var parent = node.parent; parent != null; parent = node.parent) {
      if (parent is RenderSliverMultiBoxAdaptor) {
        final index =
            (node.parentData! as SliverMultiBoxAdaptorParentData).index;
        return index == null ? null : (parent, (index, slot));
      }
      node = parent;
    }
    return null;
  }

  /// Takes the inset the box has to have where it is now. The position is only
  /// known once the layout is done, so this runs after it and asks for another
  /// if the inset has to change.
  void check() {
    if (!attached || !hasSize) return;
    final end = _scope?.endInsetOf(this) ?? 0;
    if (_row case (final sliver, final index)) {
      final insets = _rowInsets[sliver] ??= {};
      if (end > 0) {
        insets[index] = end;
      } else {
        insets.remove(index);
      }
    }
    if ((end - _end!).abs() < 0.5) return;
    _end = end;
    markNeedsLayout();
  }

  double _initialEnd() {
    if (_scope == null) return 0;
    if (_row case (final sliver, final index)) {
      return _rowInsets[sliver]?[index] ?? 0;
    }
    return 0;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      super.computeMinIntrinsicWidth(height) + endInset;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      super.computeMaxIntrinsicWidth(height) + endInset;

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(_inner(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(_inner(width));

  double _inner(double width) =>
      width.isFinite ? (width - endInset).clamp(0, double.infinity) : width;

  BoxConstraints _innerConstraints(BoxConstraints constraints, double end) =>
      constraints.deflate(EdgeInsets.only(right: end));

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final end = endInset;
    final childSize =
        child?.getDryLayout(_innerConstraints(constraints, end)) ?? Size.zero;
    return constraints.constrain(Size(childSize.width + end, childSize.height));
  }

  @override
  void performLayout() {
    final end = _end ??= _initialEnd();
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(end, 0));
    } else {
      child.layout(_innerConstraints(constraints, end), parentUsesSize: true);
      (child.parentData! as BoxParentData).offset = Offset.zero;
      size = constraints.constrain(
        Size(child.size.width + end, child.size.height),
      );
    }
    // With something to avoid the scope checks after every frame. Without,
    // only a box that still has an inset needs another look.
    if (end != 0) _scope?.scheduleCheck();
  }
}

/// Marks a [child] that is on its way to its place, such as a sheet sliding up
/// from the bottom of [frame], so that what is below it is measured where it
/// will come to rest: with its bottom on the bottom of [frame].
class OcclusionRestAnchor extends SingleChildRenderObjectWidget {
  const OcclusionRestAnchor({
    super.key,
    required this.frame,
    required Widget super.child,
  });

  /// The box [child] comes to rest in.
  final RenderObject? Function() frame;

  @override
  RenderOcclusionRestAnchor createRenderObject(BuildContext context) =>
      RenderOcclusionRestAnchor(frame);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderOcclusionRestAnchor renderObject,
  ) {
    renderObject.frame = frame;
  }
}

class RenderOcclusionRestAnchor extends RenderProxyBox {
  RenderOcclusionRestAnchor(this.frame);

  RenderObject? Function() frame;
}

/// Where [box] is in [ancestor] with every list between them scrolled to its
/// start and every sheet at rest, or null where that cannot be told. With
/// [pinned], where it is as the header its list keeps at the top.
///
/// Follows the layout only, so a page or a sheet in the middle of its
/// transition counts as arrived.
@visibleForTesting
Offset? restOffset(
  RenderBox box,
  RenderObject ancestor, {
  bool pinned = false,
}) {
  var offset = Offset.zero;
  RenderObject node = box;
  while (node != ancestor) {
    final parent = node.parent;
    if (parent == null) return null;

    if (node is RenderOcclusionRestAnchor) {
      final frame = node.frame();
      if (frame is! RenderBox || !frame.hasSize) return null;
      offset += Offset(0, frame.size.height - node.size.height);
      node = frame;
      continue;
    }

    if (parent is RenderSliver) {
      final constraints = parent.constraints;
      if (constraints.growthDirection != GrowthDirection.forward ||
          axisDirectionIsReversed(constraints.axisDirection)) {
        return null;
      }
      final parentData = node.parentData;
      // A pinned header is at the start of its list once that has scrolled.
      var main = 0.0;
      var cross = 0.0;
      if (!pinned) {
        main += constraints.precedingScrollExtent;
        if (parentData is SliverLogicalParentData) {
          main += parentData.layoutOffset ?? 0;
        }
      }
      pinned = false;
      if (parentData is SliverGridParentData) {
        cross += parentData.crossAxisOffset ?? 0;
      }
      final vertical = constraints.axis == Axis.vertical;
      RenderObject? sliver = parent;
      while (sliver is RenderSliver) {
        final parentData = sliver.parentData;
        if (parentData is SliverPhysicalParentData) {
          cross += vertical
              ? parentData.paintOffset.dx
              : parentData.paintOffset.dy;
        }
        sliver = sliver.parent;
      }
      if (sliver == null) return null;
      // A page of a horizontal list is taken to be the one on screen.
      offset += vertical ? Offset(cross, main) : Offset(0, cross);
      node = sliver;
      continue;
    }

    final parentData = node.parentData;
    if (parentData is BoxParentData) offset += parentData.offset;
    node = parent;
  }
  return offset;
}
