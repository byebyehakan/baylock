import 'package:baylock/widgets/quick_scroll_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows only a transient thumb for long content', (tester) async {
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
                child: QuickScrollRail(controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final thumb = find.byKey(const Key('quick-scroll-thumb'));
    expect(tester.widget<AnimatedOpacity>(thumb).opacity, 0);

    controller.jumpTo(500);
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(thumb).opacity, 1);
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const Key('quick-scroll-rail')),
      const Offset(0, 200),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, greaterThan(500));

    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(thumb).opacity, 0);
  });
}
