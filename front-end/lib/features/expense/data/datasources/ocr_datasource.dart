import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device text recognition (FR4.2/FR4.3) via Google ML Kit. Only pulls
/// the raw text out of the photo — merchant/date/amount parsing happens on
/// the backend (see OcrService), consistent with how the rest of this app's
/// business logic lives server-side rather than in the client.
class OcrDatasource {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFile(File(imagePath));
    final result = await _recognizer.processImage(inputImage);
    return result.text;
  }

  void dispose() => _recognizer.close();
}
