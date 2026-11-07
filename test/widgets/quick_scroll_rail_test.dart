import 'package:baylock/widgets/quick_scroll_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows for long content and quickly scrolls down', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(400, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: SingleChildScrollView(
                  controller: controller,
                  child: const SizedBox(height: 12000),
                ),
              ),
              Positioned(
                right: 6,
                top: 0,
                bottom: 0,
                child: Center(child: QuickScrollRail(controller: controller)),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('/'), findsOneWidget);
    await tester.tap(find.byTooltip('Hızlıca aşağı git'));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(0));
  });
}
