import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:denuczi_tv/features/library/domain/media_models.dart';
import 'package:denuczi_tv/features/library/presentation/category_filter_bar.dart';

void main() {
  testWidgets(
    'category picker searches and selects categories beyond the visible row',
    (tester) async {
      tester.view.physicalSize = const Size(900, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final categories = List.generate(
        120,
        (index) => MediaCategory(id: '$index', name: 'Category $index'),
      );
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 700,
                height: 44,
                child: CategoryFilterBar(
                  categories: categories,
                  selectedId: selected,
                  onSelected: (value) => selected = value,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('categoryScrollForward')), findsOneWidget);
      await tester.tap(find.byKey(const Key('openCategoryPicker')));
      await tester.pumpAndSettle();
      expect(find.byType(CategoryPickerDialog), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('categorySearch')),
        'Category 119',
      );
      await tester.pump();
      final choice = find.byKey(const ValueKey('category-119'));
      expect(choice, findsOneWidget);
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(selected, '119');
      expect(find.byType(CategoryPickerDialog), findsNothing);
    },
  );

  testWidgets(
    'canceling the category picker does not replace the active filter',
    (tester) async {
      String? selected = 'a';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 44,
              child: CategoryFilterBar(
                categories: const [
                  MediaCategory(id: 'a', name: 'Action'),
                  MediaCategory(id: 'b', name: 'Drama'),
                ],
                selectedId: selected,
                onSelected: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('openCategoryPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(selected, 'a');
    },
  );
}
