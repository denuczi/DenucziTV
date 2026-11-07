import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'explicit scrollbar works without an automatic desktop scrollbar',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScrollConfiguration(
              behavior: const MaterialScrollBehavior().copyWith(
                scrollbars: false,
              ),
              child: Scrollbar(
                controller: controller,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: controller,
                  itemCount: 100,
                  itemBuilder: (_, index) =>
                      SizedBox(height: 80, child: Text('Item $index')),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Scrollbar), findsOneWidget);
      expect(controller.hasClients, isTrue);
      final initialOffset = controller.offset;
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(controller.offset, greaterThan(initialOffset));
    },
  );
}
