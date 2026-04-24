class OcrException implements Exception {
  final String message;
  const OcrException(this.message);

  @override
  String toString() => 'OcrException: $message';
}

class EmptyImageException extends OcrException {
  const EmptyImageException() : super('No text detected in the image');
}

class HandwrittenTextException extends OcrException {
  const HandwrittenTextException()
      : super('Handwritten text detected. Only printed documents are accepted');
}
