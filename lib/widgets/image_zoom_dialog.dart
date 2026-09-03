import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Brand Colors ─────────────────────────────────────────────────────────────
const _navy       = Color(0xFF003366);
const _accentBlue = Color(0xFFA8C4E0);
const _textLight  = Color(0xFF8A9BB0);

class SnapshotImageItem {
  final String title;
  final String base64Image;

  const SnapshotImageItem({
    required this.title,
    required this.base64Image,
  });
}

/// Displays a full-screen swipeable, zoomable overlay gallery for session snapshot images.
Future<void> showImageGalleryDialog(
  BuildContext context, {
  required List<SnapshotImageItem> items,
  int initialIndex = 0,
}) {
  if (items.isEmpty) return Future.value();
  HapticFeedback.selectionClick();

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss Image Gallery',
    barrierColor: const Color(0xFFF8FAFC).withValues(alpha: 0.95),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, anim1, anim2) {
      return ImageGalleryDialog(
        items: items,
        initialIndex: initialIndex,
      );
    },
    transitionBuilder: (context, anim1, anim2, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}

/// Backward compatibility helper for single image invocation
Future<void> showImageZoomDialog(
  BuildContext context, {
  required String title,
  required String base64Image,
  String? subtitle,
}) {
  return showImageGalleryDialog(
    context,
    items: [SnapshotImageItem(title: title, base64Image: base64Image)],
    initialIndex: 0,
  );
}

class ImageGalleryDialog extends StatefulWidget {
  final List<SnapshotImageItem> items;
  final int initialIndex;

  const ImageGalleryDialog({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<ImageGalleryDialog> createState() => _ImageGalleryDialogState();
}

class _ImageGalleryDialogState extends State<ImageGalleryDialog> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;
  final GlobalKey<_ZoomableImagePageState> _currentPageKey = GlobalKey<_ZoomableImagePageState>();

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
      _isZoomed = false;
    });
    HapticFeedback.selectionClick();
  }

  void _resetCurrentZoom() {
    _currentPageKey.currentState?.resetZoom();
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.items[_currentIndex];
    final totalCount = widget.items.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background tap to dismiss when not interacting with image
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(color: Colors.transparent),
          ),

          // Swipeable PageView of zoomable images
          PageView.builder(
            controller: _pageController,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: _onPageChanged,
            itemCount: totalCount,
            itemBuilder: (context, index) {
              return _ZoomableImagePage(
                key: index == _currentIndex ? _currentPageKey : null,
                item: widget.items[index],
                onZoomStateChanged: (zoomed) {
                  if (mounted && _isZoomed != zoomed) {
                    setState(() => _isZoomed = zoomed);
                  }
                },
              );
            },
          ),

          // Top Header Bar
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Title Pill
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2EAF4)),
                          boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF1A7A4A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                currentItem.title,
                                style: const TextStyle(
                                  color: _navy,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (totalCount > 1) ...[
                              const SizedBox(width: 8),
                              Text(
                                '(${_currentIndex + 1}/$totalCount)',
                                style: const TextStyle(
                                  color: _textLight,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    // Close Button
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2EAF4)),
                          boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.close_rounded, color: _navy, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Left / Right Swipe Arrow Helpers (if multiple images)
          if (totalCount > 1 && !_isZoomed) ...[
            if (_currentIndex > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2EAF4)),
                        boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: _navy, size: 18),
                    ),
                  ),
                ),
              ),
            if (_currentIndex < totalCount - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE2EAF4)),
                        boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.arrow_forward_ios_rounded, color: _navy, size: 18),
                    ),
                  ),
                ),
              ),
          ],

          // Bottom Page Indicator Dots (if multiple images)
          if (!_isZoomed && totalCount > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2EAF4)),
                      boxShadow: [BoxShadow(color: _navy.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(totalCount, (i) {
                        final isSelected = i == _currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: isSelected ? 16 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isSelected ? _navy : _textLight.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomableImagePage extends StatefulWidget {
  final SnapshotImageItem item;
  final ValueChanged<bool> onZoomStateChanged;

  const _ZoomableImagePage({
    super.key,
    required this.item,
    required this.onZoomStateChanged,
  });

  @override
  State<_ZoomableImagePage> createState() => _ZoomableImagePageState();
}

class _ZoomableImagePageState extends State<_ZoomableImagePage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _zoomAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _transformController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    widget.onZoomStateChanged(scale > 1.05);
  }

  void resetZoom() {
    HapticFeedback.selectionClick();
    _zoomAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _zoomAnimation!.addListener(() {
      _transformController.value = _zoomAnimation!.value;
    });

    _animController.forward(from: 0);
  }

  void _handleDoubleTap(TapDownDetails details) {
    HapticFeedback.lightImpact();
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final targetMatrix = Matrix4.identity();

    if (currentScale < 1.5) {
      final position = details.localPosition;
      targetMatrix
        ..translate(-position.dx * 1.5, -position.dy * 1.5)
        ..scale(2.5);
    }

    _zoomAnimation = Matrix4Tween(
      begin: _transformController.value,
      end: targetMatrix,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));

    _zoomAnimation!.addListener(() {
      _transformController.value = _zoomAnimation!.value;
    });

    _animController.forward(from: 0);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = base64Decode(widget.item.base64Image);

    return Center(
      child: GestureDetector(
        onDoubleTapDown: _handleDoubleTap,
        onDoubleTap: () {},
        child: InteractiveViewer(
          transformationController: _transformController,
          minScale: 0.8,
          maxScale: 5.0,
          clipBehavior: Clip.none,
          boundaryMargin: const EdgeInsets.all(40),
          onInteractionStart: (details) {
            if (details.pointerCount > 1) {
              widget.onZoomStateChanged(true); // Seamlessly lock PageView during pinch
            }
          },
          onInteractionEnd: (details) {
            final scale = _transformController.value.getMaxScaleOnAxis();
            widget.onZoomStateChanged(scale > 1.05);
          },
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.94,
              maxHeight: MediaQuery.of(context).size.height * 0.78,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _navy.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(color: const Color(0xFFE2EAF4), width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Container(
                color: Colors.white,
                child: Image.memory(
                  imageBytes,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 240,
                    color: const Color(0xFFF8FAFC),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_rounded, color: _textLight, size: 48),
                        SizedBox(height: 12),
                        Text('Unable to display image', style: TextStyle(color: _textLight)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
