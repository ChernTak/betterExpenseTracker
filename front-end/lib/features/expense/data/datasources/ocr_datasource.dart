import 'dart:io';
import 'dart:ui' show Rect;

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// A word plus its position; recognizeWords keeps this for the on-device NER model, recognizeText discards it.
class RecognizedWord {
  final String text;
  final Rect boundingBox;

  const RecognizedWord({required this.text, required this.boundingBox});
}

/// Recognized words plus image dimensions, needed to normalize bounding boxes to the model's 0-1000 scale.
class RecognizedPage {
  final List<RecognizedWord> words;
  final int imageWidth;
  final int imageHeight;

  const RecognizedPage({
    required this.words,
    required this.imageWidth,
    required this.imageHeight,
  });
}

/// On-device text recognition via ML Kit; recognizeText just extracts raw text (parsing happens server-side in OcrService), recognizeWords also keeps word positions for the on-device NER model.
class OcrDatasource {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Native document scanner (edge detection, perspective correction, cropping) instead of a plain camera preview. Android only; returns null if the user cancels.
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

  /// Same as recognizeText but keeps per-word bounding boxes. Uses package:image's decodeImage+bakeOrientation (not dart:ui's instantiateImageCodec, which ignores EXIF) so dimensions match ML Kit's already-rotated coordinate space — otherwise portrait photos get a 90° mismatch that corrupts every bbox.
  Future<RecognizedPage> recognizeWords(String imagePath) async {
    final inputImage = InputImage.fromFile(File(imagePath));
    final result = await _recognizer.processImage(inputImage);

    final words = <RecognizedWord>[
      for (final block in result.blocks)
        for (final line in block.lines)
          for (final element in line.elements)
            RecognizedWord(text: element.text, boundingBox: element.boundingBox),
    ];

    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ArgumentError('Could not decode image (unrecognized format or corrupt data)');
    }
    final oriented = img.bakeOrientation(decoded);

    return RecognizedPage(words: words, imageWidth: oriented.width, imageHeight: oriented.height);
  }

  void dispose() => _recognizer.close();
}
