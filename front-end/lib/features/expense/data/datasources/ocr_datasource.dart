import 'dart:io';

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// On-device text recognition (FR4.2/FR4.3) via Google ML Kit. Only pulls
/// the raw text out of the photo — merchant/date/amount parsing happens on
/// the backend (see OcrService), consistent with how the rest of this app's
/// business logic lives server-side rather than in the client.
class OcrDatasource {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Launches ML Kit's native document scanner UI — bounding-box edge
  /// detection, perspective correction, cropping and auto-rotation — instead
  /// of a plain camera preview, so the photo handed to [recognizeText] is
  /// already isolated from background table/desk noise. Android only (see
  /// the platform check in AddExpenseScreen); returns null if the user
  /// cancels the scan.
  Future<File?> scanDocument() async {
    final documentScanner = DocumentScanner(
      options: DocumentScannerOptions(
        documentFormats: {DocumentFormat.jpeg},
        mode: ScannerMode.full,
        pageLimit: 1,
      ),
    );

    try {
      final result = await documentScanner.scanDocument();
      final images = result.images;
      final imagePath = (images != null && images.isNotEmpty) ? images.first : null;
      return imagePath != null ? File(imagePath) : null;
    } finally {
      await documentScanner.close();
    }
  }

  Future<String> recognizeText(String imagePath) async {
    final inputImage = InputImage.fromFile(File(imagePath));
    final result = await _recognizer.processImage(inputImage);
    return result.text;
  }

  void dispose() => _recognizer.close();
}
