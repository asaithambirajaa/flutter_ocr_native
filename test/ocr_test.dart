import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ocr_native/flutter_ocr_native.dart';

void main() {
  group('OcrResult', () {
    test('parses from map correctly', () {
      final result = OcrResult.fromMap({
        'text': 'Hello World',
        'isPrinted': true,
        'blocks': [
          {
            'text': 'Hello World',
            'boundingBox': {'left': 0, 'top': 0, 'width': 100, 'height': 50},
            'lines': [
              {
                'text': 'Hello World',
                'boundingBox': {'left': 0, 'top': 0, 'width': 100, 'height': 50},
                'confidence': 0.95,
                'elements': [
                  {
                    'text': 'Hello',
                    'boundingBox': {'left': 0, 'top': 0, 'width': 50, 'height': 50},
                    'confidence': 0.98,
                  },
                ],
              },
            ],
          },
        ],
      });

      expect(result.text, 'Hello World');
      expect(result.isNotEmpty, true);
      expect(result.isPrinted, true);
      expect(result.blocks.length, 1);
    });

    test('handles empty map', () {
      final result = OcrResult.fromMap({});
      expect(result.isEmpty, true);
      expect(result.isPrinted, false);
    });
  });

  group('Aadhaar masking', () {
    test('masks with spaces', () {
      final result = OcrResult.fromMap({'text': '5399 8956 2356', 'blocks': []});
      expect(result.maskAadhaar().text, 'XXXX XXXX 2356');
    });

    test('masks without spaces', () {
      final result = OcrResult.fromMap({'text': '539989562356', 'blocks': []});
      expect(result.maskAadhaar().text, 'XXXXXXXX2356');
    });

    test('does not mask non-aadhaar text', () {
      final result = OcrResult.fromMap({'text': 'DOB: 01/08/1994', 'blocks': []});
      expect(result.maskAadhaar().text, 'DOB: 01/08/1994');
    });

    test('masks elements when line contains aadhaar', () {
      final bbox = {'left': 0, 'top': 0, 'width': 50, 'height': 20};
      final result = OcrResult.fromMap({
        'text': '5399 8956 2356',
        'blocks': [
          {
            'text': '5399 8956 2356',
            'boundingBox': bbox,
            'lines': [
              {
                'text': '5399 8956 2356',
                'boundingBox': bbox,
                'confidence': 0.95,
                'elements': [
                  {'text': '5399', 'boundingBox': bbox, 'confidence': 0.95},
                  {'text': '8956', 'boundingBox': bbox, 'confidence': 0.95},
                  {'text': '2356', 'boundingBox': bbox, 'confidence': 0.95},
                ],
              },
            ],
          },
        ],
      });

      final masked = result.maskAadhaar();
      expect(masked.text, 'XXXX XXXX 2356');
      final elements = masked.blocks.first.lines.first.elements;
      expect(elements[0].text, 'XXXX');
      expect(elements[1].text, 'XXXX');
      expect(elements[2].text, '2356');
    });
  });

  group('OcrValidator', () {
    const validator = OcrValidator();
    final bbox = {'left': 0, 'top': 0, 'width': 100, 'height': 50};

    test('throws EmptyImageException for empty result', () {
      final result = OcrResult.fromMap({'text': '', 'blocks': []});
      expect(() => validator.validate(result), throwsA(isA<EmptyImageException>()));
    });

    test('throws EmptyImageException for too little text', () {
      final result = OcrResult.fromMap({
        'text': 'Hi',
        'isPrinted': true,
        'blocks': [
          {'text': 'Hi', 'boundingBox': bbox, 'lines': []},
        ],
      });
      expect(() => validator.validate(result), throwsA(isA<EmptyImageException>()));
    });

    test('throws HandwrittenTextException when isPrinted is false', () {
      final result = OcrResult.fromMap({
        'text': 'Some handwritten scribble text here',
        'isPrinted': false,
        'blocks': [
          {'text': 'Some handwritten scribble text here', 'boundingBox': bbox, 'lines': []},
        ],
      });
      expect(() => validator.validate(result), throwsA(isA<HandwrittenTextException>()));
    });

    test('passes for printed document (isPrinted true)', () {
      final result = OcrResult.fromMap({
        'text': 'Government of India DOB: 01/08/1994',
        'isPrinted': true,
        'blocks': [
          {'text': 'Government of India DOB: 01/08/1994', 'boundingBox': bbox, 'lines': []},
        ],
      });
      expect(() => validator.validate(result), returnsNormally);
    });
  });
}
