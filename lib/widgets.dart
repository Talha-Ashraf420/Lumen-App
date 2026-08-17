import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'device_profile.dart';
import 'theme.dart';

/// Directional traversal for TV remotes. Flutter can only traverse to widgets
/// that have already been built; when focus reaches the edge of a lazy list,
/// nudge its nearest scrollable and retry after the next frame.
class RemoteFocusTraversalPolicy extends ReadingOrderTraversalPolicy {
  final Set<FocusNode> _scrollPending = <FocusNode>{};

  List<ScrollableState> _scrollableAncestors(BuildContext context, Axis axis) {
    final result = <ScrollableState>[];
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        final state = element.state as ScrollableState;
        if (axisDirectionToAxis(state.axisDirection) == axis) {
          result.add(state);
        }
      }
      return true;
    });
    return result;
  }

  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final context = currentNode.context;
    if (context == null) return super.inDirection(currentNode, direction);

    final axis = switch (direction) {
      TraversalDirection.left || TraversalDirection.right => Axis.horizontal,
      TraversalDirection.up || TraversalDirection.down => Axis.vertical,
    };
    final forward =
        direction == TraversalDirection.right ||
        direction == TraversalDirection.down;

    // A lazy GridView/ListView only builds the current viewport. At its visible
    // edge, ReadingOrderTraversalPolicy can see a toolbar/sidebar outside the
    // list but not the next (unbuilt) tile, so it reports success and focus
    // appears to vanish from the catalog. Reveal the next slice first, then
    // retry traversal after those children have been built.
    for (final scrollable in _scrollableAncestors(context, axis)) {
      final position = scrollable.position;
      if (!position.hasContentDimensions) continue;
      final canMove = forward
          ? position.pixels < position.maxScrollExtent
          : position.pixels > position.minScrollExtent;
      if (!canMove) continue;

      final currentBox = context.findRenderObject();
      final viewportContext = scrollable.context;
      final viewportBox = viewportContext.findRenderObject();
      if (currentBox is! RenderBox || viewportBox is! RenderBox) continue;
      final currentRect =
          currentBox.localToGlobal(Offset.zero) & currentBox.size;
      final viewportRect =
          viewportBox.localToGlobal(Offset.zero) & viewportBox.size;
      final nearScrollableEdge = switch ((axis, forward)) {
        (Axis.horizontal, true) =>
          currentRect.right >= viewportRect.right - currentRect.width * .8,
        (Axis.horizontal, false) =>
          currentRect.left <= viewportRect.left + currentRect.width * .8,
        (Axis.vertical, true) =>
          currentRect.bottom >= viewportRect.bottom - currentRect.height * .8,
        (Axis.vertical, false) =>
          currentRect.top <= viewportRect.top + currentRect.height * .8,
      };
      if (!nearScrollableEdge) continue;
      if (_scrollPending.contains(currentNode)) return true;

      final itemExtent = axis == Axis.horizontal
          ? currentRect.width
          : currentRect.height;
      final amount = (itemExtent * 1.15).clamp(72.0, 260.0);
      final target = (position.pixels + (forward ? amount : -amount)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      _scrollPending.add(currentNode);
      position.jumpTo(target);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollPending.remove(currentNode);
        if (currentNode.hasFocus && currentNode.context != null) {
          super.inDirection(currentNode, direction);
        }
      });
      return true;
    }
    return super.inDirection(currentNode, direction);
  }
}

/// Keeps standard Material controls visible too (IconButton, Slider, switch,
/// dialog buttons), not only Lumen's custom remote widgets.
class RemoteFocusVisibility extends StatefulWidget {
  const RemoteFocusVisibility({super.key, required this.child});
  final Widget child;

  @override
  State<RemoteFocusVisibility> createState() => _RemoteFocusVisibilityState();
}

class _RemoteFocusVisibilityState extends State<RemoteFocusVisibility> {
  FocusNode? _last;
  TraversalDirection? _lastDirection;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_recordDirection);
    FocusManager.instance.addListener(_focusChanged);
  }

  bool _recordDirection(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    _lastDirection = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    return false;
  }

  void _focusChanged() {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || identical(node, _last)) return;
    _last = node;
    final direction = _lastDirection;
    _lastDirection = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = node.context;
      if (!mounted || !node.hasFocus || context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: DeviceProfile.isTelevision
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignmentPolicy:
            direction == TraversalDirection.up ||
                direction == TraversalDirection.left
            ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
            : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_recordDirection);
    FocusManager.instance.removeListener(_focusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Text fields consume arrow keys for cursor movement. On TV, Up and Down are
/// navigation commands, so pass them back to directional focus traversal.
class RemoteTextInput extends StatelessWidget {
  const RemoteTextInput({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final direction = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowUp => TraversalDirection.up,
        LogicalKeyboardKey.arrowDown => TraversalDirection.down,
        _ => null,
      };
      if (direction == null) return KeyEventResult.ignored;
      return FocusManager.instance.primaryFocus?.focusInDirection(direction) ==
              true
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    },
    child: child,
  );
}

/// Turns provider-style filenames into human-facing titles without stripping a
/// meaningful year that is actually part of a title (for example "1984").
String cleanMediaTitle(String raw) {
  var title = raw.trim();
  title = title.replaceFirst(RegExp(r'^\s*[A-Z]{2,3}\s*[|:\-]\s*'), '');
  title = title.replaceAll(RegExp(r'\(\s*(?:19|20)\d{2}\s*\)'), ' ');
  title = title.replaceAll(
    RegExp(
      r'[\(\[]\s*(?:4K|UHD|FHD|HD|SD|HDR|DV|HEVC|H\s?26[45]|X26[45]|1080P|720P|2160P|MULTI|DUAL|SUB|DUB)\s*[\)\]]',
      caseSensitive: false,
    ),
    ' ',
  );
  title = title.replaceAll(
    RegExp(
      r'\b(?:4K|UHD|FHD|HD|SD|HDR|HEVC|1080P|720P|2160P)\b',
      caseSensitive: false,
    ),
    ' ',
  );
  title = title.replaceAll(RegExp(r'[._]+'), ' ');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  title = title.replaceAll(RegExp(r'\s*[-|·•:]\s*$'), '').trim();
  return title.isEmpty ? raw : title;
}

/// Renders provider artwork and Lumen's bundled demo artwork through one API.
///
/// Provider images retain the existing disk/memory cache. `asset://` sources
/// never touch the network, which keeps Demo Mode genuinely offline.
class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.source,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.placeholder,
    this.error,
    this.filterQuality = FilterQuality.medium,
  });

  final String source;
  final BoxFit fit;
  final Alignment alignment;
  final int? memCacheWidth;
  final Widget? placeholder;
  final Widget? error;
  final FilterQuality filterQuality;

  static bool isAsset(String source) => source.startsWith('asset://');

  @override
  Widget build(BuildContext context) {
    if (isAsset(source)) {
      return Image.asset(
        source.substring('asset://'.length),
        fit: fit,
        alignment: alignment,
        cacheWidth: memCacheWidth,
        filterQuality: filterQuality,
        errorBuilder: (_, _, _) => error ?? const SizedBox.shrink(),
      );
    }
    return CachedNetworkImage(
      imageUrl: source,
      fit: fit,
      alignment: alignment,
      memCacheWidth: memCacheWidth,
      // Catalog cards already have an entrance transition. Starting another
      // fade controller for every image arriving during a fast fling creates a
      // burst of concurrent animations and visible frame misses.
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      useOldImageOnUrlChange: true,
      placeholder: placeholder == null ? null : (_, _) => placeholder!,
      errorWidget: (_, _, _) => error ?? const SizedBox.shrink(),
    );
  }
}

/// Wraps a tappable element so it responds to BOTH mouse hover AND TV
/// remote / D-pad focus. [builder] is given an `active` flag (hovered or
/// focused) so callers can reuse their existing hover styling as the focus
/// highlight. Enter / Space / D-pad-center / gamepad-A all activate [onTap];
/// arrow keys move focus between [FocusableTap]s automatically (Flutter's
/// default directional traversal), and the focused widget scrolls into view.
class FocusableTap extends StatefulWidget {
  final Widget Function(BuildContext context, bool active) builder;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final double focusRadius;
  final bool showFocusRing;
  final FocusOnKeyEventCallback? onKeyEvent;
  const FocusableTap({
    super.key,
    required this.builder,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.focusRadius = 16,
    this.showFocusRing = true,
    this.onKeyEvent,
  });
  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _hover = false;
  bool _focus = false;
  FocusNode? _ownedFocusNode;
  FocusOnKeyEventCallback? _previousNodeHandler;
  late final FocusOnKeyEventCallback _installedNodeHandler = _handleKeyEvent;

  static const _activators = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.accept): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.execute): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
  };

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _attachKeyHandler();
  }

  @override
  void didUpdateWidget(FocusableTap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      _detachKeyHandler(oldWidget.focusNode);
      _attachKeyHandler();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final result = widget.onKeyEvent?.call(node, event);
    if (result != null && result != KeyEventResult.ignored) return result;
    return _previousNodeHandler?.call(node, event) ?? KeyEventResult.ignored;
  }

  void _attachKeyHandler() {
    final external = widget.focusNode;
    if (external == null) {
      _ownedFocusNode = FocusNode(onKeyEvent: _installedNodeHandler);
      _previousNodeHandler = null;
      return;
    }
    _previousNodeHandler = external.onKeyEvent;
    external.onKeyEvent = _installedNodeHandler;
  }

  void _detachKeyHandler(FocusNode? external) {
    if (external != null &&
        identical(external.onKeyEvent, _installedNodeHandler)) {
      external.onKeyEvent = _previousNodeHandler;
    }
    _ownedFocusNode?.dispose();
    _ownedFocusNode = null;
    _previousNodeHandler = null;
  }

  @override
  void dispose() {
    _detachKeyHandler(widget.focusNode);
    super.dispose();
  }

  void _focusChanged(bool value) {
    if (_focus != value) setState(() => _focus = value);
    widget.onFocusChange?.call(value);
    // The app-level RemoteFocusVisibility handles every focused control. On TV
    // a second concurrent ensureVisible animation fights explicit grid scrolls
    // and can leave a lazy tile detached while it owns focus.
    if (!value || DeviceProfile.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final detector = FocusableActionDetector(
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      shortcuts: _activators,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onFocusChange: _focusChanged,
      child: Semantics(
        button: true,
        onTap: widget.onTap,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: lumenMotionFast,
            foregroundDecoration: widget.showFocusRing && _focus
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.focusRadius),
                    border: Border.all(color: accentInk, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: isDark ? .48 : .32),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  )
                : null,
            child: widget.builder(context, _hover || _focus),
          ),
        ),
      ),
    );
    return detector;
  }
}

/// Drop-in replacement for a touch-only [GestureDetector]. It adds a focus
/// node, visible focus ring, D-pad-center/Enter activation and scroll-to-focus
/// without requiring every screen to implement its own TV behavior.
class RemoteTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final HitTestBehavior? behavior;
  final bool autofocus;
  final String? semanticLabel;
  final double focusRadius;
  final bool showFocusRing;
  final ValueChanged<bool>? onFocusChange;
  final FocusOnKeyEventCallback? onKeyEvent;

  const RemoteTap({
    super.key,
    required this.child,
    required this.onTap,
    this.focusNode,
    this.behavior,
    this.autofocus = false,
    this.semanticLabel,
    this.focusRadius = 16,
    this.showFocusRing = true,
    this.onFocusChange,
    this.onKeyEvent,
  });

  @override
  State<RemoteTap> createState() => _RemoteTapState();
}

/// A compact back control with deterministic bounds on desktop and TV.
/// Unlike IconButton's InkResponse it cannot inherit a page-sized focus oval.
class LumenBackButton extends StatelessWidget {
  const LumenBackButton({
    super.key,
    required this.onTap,
    this.autofocus = true,
  });

  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => RemoteTap(
    autofocus: autofocus,
    semanticLabel: 'Back',
    focusRadius: 14,
    onTap: onTap,
    child: Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .46),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.arrow_back_rounded,
        color: Colors.white,
        size: 23,
      ),
    ),
  );
}

class _RemoteTapState extends State<RemoteTap> {
  bool _focused = false;
  bool _hovered = false;
  FocusNode? _ownedFocusNode;
  FocusOnKeyEventCallback? _previousNodeHandler;
  late final FocusOnKeyEventCallback _installedNodeHandler = _handleKeyEvent;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    _attachKeyHandler();
  }

  @override
  void didUpdateWidget(RemoteTap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      _detachKeyHandler(oldWidget.focusNode);
      _attachKeyHandler();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final result = widget.onKeyEvent?.call(node, event);
    if (result != null && result != KeyEventResult.ignored) return result;
    return _previousNodeHandler?.call(node, event) ?? KeyEventResult.ignored;
  }

  void _attachKeyHandler() {
    final external = widget.focusNode;
    if (external == null) {
      _ownedFocusNode = FocusNode(
        debugLabel: widget.semanticLabel,
        onKeyEvent: _installedNodeHandler,
      );
      _previousNodeHandler = null;
      return;
    }
    _previousNodeHandler = external.onKeyEvent;
    external.onKeyEvent = _installedNodeHandler;
  }

  void _detachKeyHandler(FocusNode? external) {
    if (external != null &&
        identical(external.onKeyEvent, _installedNodeHandler)) {
      external.onKeyEvent = _previousNodeHandler;
    }
    _ownedFocusNode?.dispose();
    _ownedFocusNode = null;
    _previousNodeHandler = null;
  }

  @override
  void dispose() {
    _detachKeyHandler(widget.focusNode);
    super.dispose();
  }

  void _onFocusChange(bool value) {
    if (_focused != value) setState(() => _focused = value);
    widget.onFocusChange?.call(value);
    if (!value || DeviceProfile.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final enabled = widget.onTap != null;
    final active = enabled && (_focused || _hovered);
    final detector = FocusableActionDetector(
      enabled: enabled,
      focusNode: _effectiveFocusNode,
      autofocus: widget.autofocus,
      mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      shortcuts: _FocusableTapState._activators,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onFocusChange: _onFocusChange,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.semanticLabel,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: active ? 1.025 : 1,
          duration: lumenMotionFast,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: lumenMotionFast,
            foregroundDecoration: widget.showFocusRing && _focused
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.focusRadius),
                    border: Border.all(color: accentInk, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: isDark ? .48 : .32),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ],
                  )
                : null,
            child: GestureDetector(
              behavior: widget.behavior ?? HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    return detector;
  }
}

/// Lumen's broadcast lockup. The viewport says television, the triangle says
/// playback, and its three outgoing bars read as both live signal and light.
/// It is rendered natively so it stays crisp and follows the selected accent.
class Wordmark extends StatelessWidget {
  final double size; // text font size
  const Wordmark({super.key, this.size = 34});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        LumenMark(size: size * 1.08),
        SizedBox(width: size * 0.24),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'LUMEN',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: size,
                    fontWeight: FontWeight.w600,
                    color: textHi,
                    letterSpacing: -1.8,
                    height: 0.92,
                  ),
                ),
                SizedBox(width: size * 0.16),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: size * 0.13,
                    vertical: size * 0.075,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(size * 0.16),
                  ),
                  child: Text(
                    'TV',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: size * 0.28,
                      fontWeight: FontWeight.w800,
                      color: onAccent,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: size * 0.13),
            Text(
              'LIVE  •  FILMS  •  SERIES',
              style: GoogleFonts.spaceGrotesk(
                fontSize: size * 0.18,
                fontWeight: FontWeight.w600,
                color: muted,
                letterSpacing: size * 0.055,
                height: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Standalone mark used in the compact navigation dock.
class LumenMark extends StatelessWidget {
  final double size; // height of the mark
  final Color? signal;
  final Color? frame;

  const LumenMark({super.key, this.size = 24, this.signal, this.frame});

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _LumenMarkPainter(
        signal: signal ?? accentInk,
        frame: frame ?? textHi,
      ),
    );
  }
}

class _LumenMarkPainter extends CustomPainter {
  final Color signal;
  final Color frame;
  _LumenMarkPainter({required this.signal, required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    final framePaint = Paint()
      ..color = frame
      ..isAntiAlias = true;
    final signalPaint = Paint()
      ..color = signal
      ..isAntiAlias = true;
    final w = size.width;
    final h = size.height;
    final r = Radius.circular(w * 0.055);

    canvas.drawRRect(
      RRect.fromLTRBR(w * .20, h * .215, w * .31, h * .79, r),
      framePaint,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(w * .20, h * .215, w * .58, h * .315, r),
      framePaint,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(w * .20, h * .69, w * .58, h * .79, r),
      framePaint,
    );

    final tri = Path()
      ..moveTo(w * .36, h * .37)
      ..lineTo(w * .36, h * .64)
      ..lineTo(w * .63, h * .505)
      ..close();
    canvas.drawPath(tri, signalPaint);
    canvas.drawRRect(
      RRect.fromLTRBR(w * .62, h * .325, w * .785, h * .397, r),
      signalPaint,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(w * .63, h * .47, w * .865, h * .542, r),
      signalPaint,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(w * .62, h * .615, w * .785, h * .687, r),
      signalPaint,
    );
  }

  @override
  bool shouldRepaint(_LumenMarkPainter old) =>
      old.signal != signal || old.frame != frame;
}

/// Subtle scale-up on mouse hover (desktop affordance; no-op on touch).
class HoverScale extends StatefulWidget {
  final Widget child;
  final double scale;
  const HoverScale({super.key, required this.child, this.scale = 1.04});
  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedScale(
        scale: _hover ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Frosted "liquid glass" surface (used for nav / menus / sheets).
class Glass extends StatelessWidget {
  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsets? padding;
  final Color? tint;
  const Glass({
    super.key,
    required this.child,
    this.blur = 18,
    this.radius = 22,
    this.padding,
    this.tint,
  });
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final tintColor = tint ?? surfaceHi;
    final tintAlpha = tint == null
        ? (isDark ? 0.55 : 0.72)
        : tintColor.a < 0.99
        ? tintColor.a
        : (isDark ? 0.18 : 0.13);
    final topTint = Color.alphaBlend(
      Colors.white.withValues(alpha: isDark ? 0.045 : 0.38),
      tintColor,
    );
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            topTint.withValues(alpha: tintAlpha),
            tintColor.withValues(alpha: tintAlpha),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: lineStrong),
      ),
      child: child,
    );
    // Backdrop filters force an offscreen render pass. A profile page can have
    // several of them visible simultaneously, which is expensive on common TV
    // chipsets and makes remote focus feel delayed. Keep the same surface and
    // border on televisions without the live blur pass.
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DeviceProfile.isTelevision
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: content,
            ),
    );
  }
}

/// Editorial header used by Lumen's secondary destinations. It gives utility
/// pages the same hierarchy as the content-led Home screen without forcing
/// every route into a conventional platform AppBar.
class EditorialPageHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onBack;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const EditorialPageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onBack,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 18),
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (onBack != null) ...[
          RemoteTap(
            autofocus: true,
            semanticLabel: 'Go back',
            focusRadius: 14,
            onTap: onBack,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: surfaceHi.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: line),
              ),
              child: Icon(Icons.arrow_back_rounded, color: textHi, size: 20),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accentInk.withValues(alpha: isDark ? 0.18 : 0.12),
                accentInk.withValues(alpha: isDark ? 0.08 : 0.06),
              ],
            ),
            borderRadius: BorderRadius.circular(lumenRadiusMd),
            border: Border.all(
              color: accentInk.withValues(alpha: isDark ? 0.24 : 0.38),
            ),
          ),
          child: Icon(icon, color: accentInk, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(eyebrow.toUpperCase(), style: kSection(color: accentInk)),
              const SizedBox(height: 3),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: kTitle().copyWith(fontSize: 25),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subtle, fontSize: 12.5, height: 1.3),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 14), trailing!],
      ],
    ),
  );
}

/// A focused empty state with a quiet brand motif and optional next action.
class LumenEmptyState extends StatelessWidget {
  final IconData icon;
  final String eyebrow;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const LumenEmptyState({
    super.key,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Glass(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: accentInk.withValues(
                            alpha: isDark ? 0.25 : 0.38,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: accentInk.withValues(
                          alpha: isDark ? 0.14 : 0.09,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(icon, color: accentInk, size: 29),
                    ),
                    Positioned(
                      right: 3,
                      top: 7,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: accentInk,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(eyebrow.toUpperCase(), style: kSection(color: accentInk)),
                const SizedBox(height: 7),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, height: 1.5, fontSize: 13.5),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 20),
                  RemoteTap(
                    onTap: onAction,
                    focusRadius: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        actionLabel!,
                        style: TextStyle(
                          color: onAccent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact filter control with a consistent remote-focus treatment.
class LumenFilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;
  final bool autofocus;

  const LumenFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChange,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => RemoteTap(
    focusNode: focusNode,
    autofocus: autofocus,
    onKeyEvent: onKeyEvent,
    onFocusChange: onFocusChange,
    onTap: onTap,
    focusRadius: 13,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? accent : surfaceHi.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: selected ? accent : line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: selected ? onAccent : muted),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: selected ? onAccent : textHi,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

/// The single, consistent search field used across the whole app.
class SearchField extends StatefulWidget {
  final String hint;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap; // read-only mode (e.g. Home → opens Search)
  final bool readOnly;
  final Widget? trailing;
  const SearchField({
    super.key,
    required this.hint,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.trailing,
  });

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _attachFocusNode(widget.focusNode);
  }

  void _attachFocusNode(FocusNode? supplied) {
    _ownsFocusNode = supplied == null;
    _focusNode = supplied ?? FocusNode();
    _focusNode.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode == widget.focusNode) return;
    _focusNode.removeListener(_focusChanged);
    if (_ownsFocusNode) _focusNode.dispose();
    _attachFocusNode(widget.focusNode);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_focusChanged);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = !widget.readOnly && _focusNode.hasFocus;
    final field = Container(
      height: 50,
      padding: const EdgeInsets.fromLTRB(17, 0, 7, 0),
      decoration: BoxDecoration(
        color: focused
            ? surfaceHi.withValues(alpha: 0.92)
            : surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: focused ? accentInk : line,
          width: focused ? 3 : 1,
        ),
        boxShadow: focused && DeviceProfile.isTelevision
            ? glow(accent, blur: 18, a: .45)
            : null,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: focused ? accent : muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: widget.readOnly
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.hint,
                      style: TextStyle(color: subtle, fontSize: 15),
                    ),
                  )
                : RemoteTextInput(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      onChanged: widget.onChanged,
                      onSubmitted: widget.onSubmitted,
                      // Keep the remote anchored to Search after the IME's
                      // Search/Done action closes. The user can then press
                      // center to reopen the keyboard or Down to reach filters.
                      onEditingComplete: () {},
                      textInputAction: TextInputAction.search,
                      autocorrect: false,
                      enableSuggestions: false,
                      style: const TextStyle(fontSize: 15.5),
                      cursorColor: accent,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        hintText: widget.hint,
                        hintStyle: TextStyle(color: subtle, fontSize: 15),
                      ),
                    ),
                  ),
          ),
          if (widget.trailing != null) widget.trailing!,
        ],
      ),
    );
    if (widget.onTap != null) {
      return FocusableTap(
        onTap: widget.onTap!,
        builder: (context, active) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: active ? accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: field,
        ),
      );
    }
    return field;
  }
}

/// Ambient drifting aurora background.
class Aurora extends StatelessWidget {
  const Aurora({super.key});
  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final animate =
        !DeviceProfile.isTelevision && !MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: bg)),
            Positioned(
              top: -190,
              left: -150,
              child: _blob(
                accent.withValues(alpha: isDark ? 0.20 : 0.11),
                430,
                animated: animate,
              ),
            ),
            Positioned(
              top: 30,
              right: -180,
              child: _blob(
                accentDark.withValues(alpha: isDark ? 0.13 : 0.07),
                390,
              ),
            ),
            Positioned(
              bottom: -210,
              left: 10,
              child: _blob(
                const Color(0xFF0F5B50).withValues(alpha: isDark ? 0.28 : 0.08),
                400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(Color c, double s, {bool animated = false}) {
    final blob = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
      ),
    );
    if (!animated) return blob;
    // One compositor animation is enough to keep the background alive. The old
    // version ran three perpetual tickers per visited page.
    return blob
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .moveY(
          begin: -18,
          end: 18,
          duration: 7.seconds,
          curve: Curves.easeInOut,
        );
  }
}

/// Branded loading splash.
/// Wraps a skeleton layout in a single "light" band that sweeps across it —
/// the shared engine behind [BrandedLoading] and [GridLoading].
class _ShimmerSweep extends StatefulWidget {
  final Widget child;
  const _ShimmerSweep({required this.child});
  @override
  State<_ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<_ShimmerSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = surfaceHi;
    final hi = Color.alphaBlend(
      Colors.white.withValues(alpha: isDark ? 0.10 : 0.65),
      surfaceHi,
    );
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final x =
            -1.4 +
            2.8 * _c.value; // band travels left → right, off-screen both ends
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 0.6, 0),
            end: Alignment(x + 0.6, 0),
            colors: [base, hi, base],
            stops: const [0.3, 0.5, 0.7],
          ).createShader(rect),
          child: child,
        );
      },
    );
  }
}

Widget _skelBox(double w, double h, {double r = 12}) => Container(
  width: w,
  height: h,
  decoration: BoxDecoration(
    color: surfaceHi,
    borderRadius: BorderRadius.circular(r),
  ),
);

/// A quiet artwork field for detail pages while a real backdrop is decoding,
/// or when a provider only supplied poster art. It avoids stretching a portrait
/// poster across the hero and works in both light and dark themes.
class DetailBackdropPlaceholder extends StatelessWidget {
  const DetailBackdropPlaceholder({
    super.key,
    required this.icon,
    this.loading = false,
  });

  final IconData icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final visual = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surfaceHi, surface, bg],
        ),
      ),
      child: Align(
        alignment: const Alignment(0.72, -0.08),
        child: Icon(
          icon,
          size: MediaQuery.sizeOf(context).width >= 700 ? 190 : 120,
          color: accentInk.withValues(alpha: isDark ? 0.13 : 0.09),
        ),
      ),
    );
    return loading ? _ShimmerSweep(child: visual) : visual;
  }
}

/// Short skeleton copy used inside a detail hero while provider metadata is
/// still arriving. The page remains usable, but loading is visually deliberate.
class DetailMetadataSkeleton extends StatelessWidget {
  const DetailMetadataSkeleton({super.key, this.maxWidth = 620});

  final double maxWidth;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: _ShimmerSweep(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _skelBox(double.infinity, 12, r: 6),
          const SizedBox(height: 9),
          FractionallySizedBox(
            widthFactor: 0.72,
            child: _skelBox(double.infinity, 12, r: 6),
          ),
        ],
      ),
    ),
  );
}

/// A shimmer skeleton loader — a hero block + poster rows with a light sweep
/// gliding across. No spinner, no logo, no text; it reads as the page
/// materialising. Used for full pages such as Home and media details.
class BrandedLoading extends StatelessWidget {
  final bool background;
  const BrandedLoading({super.key, this.background = false});

  Widget _posterRow() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    physics: const NeverScrollableScrollPhysics(),
    child: Row(
      children: [
        for (var i = 0; i < 8; i++)
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _skelBox(120, 180, r: 16),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final skeleton = Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _skelBox(double.infinity, 260, r: 26),
            const SizedBox(height: 30),
            _skelBox(170, 18, r: 6),
            const SizedBox(height: 16),
            _posterRow(),
            const SizedBox(height: 30),
            _skelBox(220, 18, r: 6),
            const SizedBox(height: 16),
            _posterRow(),
          ],
        ),
      ),
    );
    final shimmer = _ShimmerSweep(child: skeleton);
    if (!background) return shimmer;
    return Stack(children: [Aurora(), shimmer]);
  }
}

/// A shimmer skeleton shaped like a poster/channel grid — matches what's about
/// to load on Search / Movies / Series / Live, so there's no misleading hero
/// block. Fills its parent.
class GridLoading extends StatelessWidget {
  final bool channel;
  const GridLoading({super.key, this.channel = false});
  @override
  Widget build(BuildContext context) {
    return _ShimmerSweep(
      child: LayoutBuilder(
        builder: (context, c) {
          final tile = channel ? 150.0 : 136.0;
          final cols = (c.maxWidth / tile).floor().clamp(2, 8);
          return GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              childAspectRatio: channel ? 0.76 : 0.66,
              crossAxisSpacing: 13,
              mainAxisSpacing: 20,
            ),
            itemCount: cols * 3,
            itemBuilder: (_, i) => DecoratedBox(
              decoration: BoxDecoration(
                color: surfaceHi,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Compact editorial action used by hero and detail surfaces.
class PillButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.filled = true,
  });
  @override
  Widget build(BuildContext context) {
    final fg = filled ? onAccent : textHi;
    return FocusableTap(
      onTap: onTap,
      builder: (context, active) => AnimatedScale(
        scale: active ? 1.025 : 1.0,
        duration: lumenMotionFast,
        curve: Curves.easeOut,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: filled
                ? accent
                : (active ? surfaceRaised : surfaceHi.withValues(alpha: 0.82)),
            borderRadius: BorderRadius.circular(lumenRadiusMd),
            border: filled
                ? Border.all(
                    color: active
                        ? foregroundFor(accent).withValues(alpha: .32)
                        : accent,
                  )
                : Border.all(
                    color: active ? accentInk : lineStrong,
                    width: active ? 1.5 : 1,
                  ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: accent.withValues(
                        alpha: active
                            ? (isDark ? .32 : .22)
                            : (isDark ? .18 : .12),
                      ),
                      blurRadius: active ? 28 : 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Editorial section marker: a signal bar, a generous title and a quiet link.
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;
  const SectionHeader({super.key, required this.title, this.onSeeAll});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 18, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 3,
            height: 29,
            margin: const EdgeInsets.only(right: 12, bottom: 1),
            decoration: BoxDecoration(
              color: accentInk,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: kTitle(),
            ),
          ),
          const SizedBox(width: 12),
          if (onSeeAll != null)
            RemoteTap(
              onTap: onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Open collection',
                      style: TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Icon(
                      Icons.arrow_outward_rounded,
                      color: accentInk,
                      size: 15,
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

/// Standard width for a poster card in a shelf (keeps everything consistent).
const double kPosterW = 134;
double posterShelfHeight({bool live = false}) => live
    ? kPosterW + 44
    : kPosterW * 1.5 + 4; // poster (info overlaid) / channel logo + name

/// Premium movie/series poster tile: art fills the card, title + year + rating
/// overlaid on a gradient; hover reveals a play affordance + accent glow.
class PosterCard extends StatelessWidget {
  final String name;
  final String image;
  final double rating;
  final String? subtitle; // year
  final int index;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;
  const PosterCard({
    super.key,
    required this.name,
    required this.image,
    required this.onTap,
    this.rating = 0,
    this.subtitle,
    this.index = 0,
    this.autofocus = false,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChange,
  });

  @override
  Widget build(BuildContext context) {
    final interactive = FocusableTap(
      autofocus: autofocus,
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      onFocusChange: onFocusChange,
      onTap: onTap,
      builder: (context, active) => _visual(context, active),
    );
    // Animate the first viewport, not an entire 50+ item result page at once.
    if (index >= 12) return interactive;
    return interactive
        .animate()
        .fadeIn(duration: 320.ms, delay: (index * 30).ms)
        .slideY(begin: 0.1, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _visual(BuildContext context, bool active) {
    final w = this;
    const radius = 16.0;
    final card = AspectRatio(
      aspectRatio: 2 / 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _Fallback(),
            if (w.image.isNotEmpty)
              MediaImage(
                source: w.image,
                fit: BoxFit.cover,
                // Provider posters are frequently multi-megapixel files. Decode
                // them near their on-screen size to avoid memory churn and GC
                // pauses while a catalog is flung.
                memCacheWidth: (220 * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(320, 640),
              ),
            // bottom scrim for the title
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black, Colors.transparent],
                  stops: [0.0, 0.68],
                ),
              ),
            ),
            // title + year
            Positioned(
              left: 11,
              right: 11,
              bottom: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    w.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  if (w.subtitle != null && w.subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        w.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (w.rating > 0)
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xD9141719),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, color: gold, size: 12),
                      const SizedBox(width: 3),
                      Text(
                        w.rating.toStringAsFixed(1),
                        style: TextStyle(
                          color: gold,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // hover / focus veil + play
            AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.22),
                child: Center(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: glow(accent),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: onAccent,
                      size: 25,
                    ),
                  ),
                ),
              ),
            ),
            // hairline edge
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: active
                      ? accentInk.withValues(alpha: 0.72)
                      : Colors.white.withValues(alpha: 0.09),
                  width: active ? 1.5 : 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return AnimatedScale(
      scale: active ? 1.035 : 1.0,
      duration: lumenMotion,
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: lumenMotion,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.34),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
        ),
        child: card,
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: surfaceHi),
    child: Center(
      child: Icon(Icons.movie_creation_outlined, color: subtle, size: 28),
    ),
  );
}

/// A polished live-TV tile: the channel logo centred on an elevated surface
/// (logos are often transparent/odd-shaped, so they get a clean backdrop),
/// a LIVE badge, and the channel name below.
class ChannelCard extends StatelessWidget {
  final String name;
  final String logo;
  final VoidCallback onTap;
  final int index;
  final FocusNode? focusNode;
  final FocusOnKeyEventCallback? onKeyEvent;
  final ValueChanged<bool>? onFocusChange;
  const ChannelCard({
    super.key,
    required this.name,
    required this.logo,
    required this.onTap,
    this.index = 0,
    this.focusNode,
    this.onKeyEvent,
    this.onFocusChange,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [surfaceHi, surface],
              ),
              border: Border.all(color: line),
              boxShadow: glow(Colors.black, blur: 12, y: 6, a: 0.4),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: logo.isNotEmpty
                      ? MediaImage(
                          source: logo,
                          fit: BoxFit.contain,
                          memCacheWidth:
                              (180 * MediaQuery.devicePixelRatioOf(context))
                                  .round()
                                  .clamp(256, 512),
                          error: Icon(
                            Icons.live_tv_rounded,
                            color: subtle,
                            size: 30,
                          ),
                        )
                      : Icon(Icons.live_tv_rounded, color: subtle, size: 30),
                ),
                Positioned(
                  left: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B5C),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.white, size: 5),
                        SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
    final interactive = FocusableTap(
      focusNode: focusNode,
      onKeyEvent: onKeyEvent,
      onFocusChange: onFocusChange,
      onTap: onTap,
      builder: (context, active) => AnimatedScale(
        scale: active ? 1.035 : 1.0,
        duration: lumenMotionFast,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: lumenMotionFast,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.4),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : null,
          ),
          child: tile,
        ),
      ),
    );
    if (index >= 12) return interactive;
    return interactive
        .animate()
        .fadeIn(duration: 300.ms, delay: (index * 28).ms)
        .slideY(begin: 0.08, end: 0, curve: Curves.easeOutCubic);
  }
}
