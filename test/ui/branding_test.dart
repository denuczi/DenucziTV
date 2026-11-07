import 'package:denuczi_tv/shared/widgets/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sidebar icon uses canonical asset and one image layer', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BrandMark(size: 36))),
    );
    final mark = find.byType(BrandMark);
    final image = tester.widget<Image>(
      find.descendant(of: mark, matching: find.byType(Image)),
    );
    expect(image.image, isA<ResizeImage>());
    final source = (image.image as ResizeImage).imageProvider;
    expect(source, isA<AssetImage>());
    expect(
      (source as AssetImage).assetName,
      'assets/branding/denuczitv_app_icon.png',
    );
    expect(image.width, 36);
    expect(image.height, 36);
    expect(
      find.descendant(of: mark, matching: find.byType(ClipRRect)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings icon requests an appropriately sized HiDPI decode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(devicePixelRatio: 2),
          child: Scaffold(body: BrandMark(size: 52)),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect(resized.width, 104);
    expect(image.width, 52);
    expect(image.height, 52);
    expect(tester.takeException(), isNull);
  });
}
