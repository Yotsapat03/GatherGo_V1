import 'package:flutter/material.dart';

class BidirectionalTableScroller extends StatelessWidget {
  final ScrollController horizontalController;
  final ScrollController verticalController;
  final double minWidth;
  final Widget child;

  const BidirectionalTableScroller({
    super.key,
    required this.horizontalController,
    required this.verticalController,
    required this.minWidth,
    required this.child,
  });

  void _dragBy(DragUpdateDetails details) {
    if (horizontalController.hasClients) {
      final next = (horizontalController.offset - details.delta.dx).clamp(
        0.0,
        horizontalController.position.maxScrollExtent,
      );
      if (next != horizontalController.offset) {
        horizontalController.jumpTo(next);
      }
    }

    if (verticalController.hasClients) {
      final next = (verticalController.offset - details.delta.dy).clamp(
        0.0,
        verticalController.position.maxScrollExtent,
      );
      if (next != verticalController.offset) {
        verticalController.jumpTo(next);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanUpdate: _dragBy,
      child: Scrollbar(
        controller: horizontalController,
        thumbVisibility: true,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          controller: horizontalController,
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Scrollbar(
              controller: verticalController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: verticalController,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
