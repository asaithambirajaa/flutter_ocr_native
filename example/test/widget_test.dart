import 'package:flutter_test/flutter_test.dart';
import 'package:ocr_example/main.dart';

void main() {
  testWidgets('App renders', (tester) async {
    await tester.pumpWidget(const OcrExampleApp());
    expect(find.text('OCR Reader'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
  });
}
