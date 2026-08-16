import 'dart:io';
import 'dart:ui' show Rect;

import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

/// One word (ML Kit's [TextElement]) plus its position on the page —
/// [recognizeText] discards this; [recognizeWords] keeps it, needed by the
/// on-device receipt NER model (see lib/services/receipt_ner/), which reads
/// layout position, not just flat text.
class RecognizedWord {
  final String text;
  final Rect boundingBox;

  const RecognizedWord({required this.text, required this.boundingBox});
}

/// A photo's recognized words plus the pixel dimensions they're measured
/// against — needed to normalize bounding boxes to the 0-1000 scale the
/// model was trained on (see ai/receipt_ner_gpu_training_v3.ipynb's
/// `normalize_bbox`).
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

/// On-device text recognition (FR4.2/FR4.3) via Google ML Kit. [recognizeText]
/// only pulls the raw text out of the photo — merchant/date/amount parsing
/// happens on the backend (see OcrService), consistent with how the rest of
/// this app's business logic lives server-side rather than in the client.
/// [recognizeWords] is the newer, second consumer: the on-device receipt NER
/// model needs word positions, which the backend's regex parser never did.
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

  /// Same ML Kit recognition pass as [recognizeText], but keeps each word's
  /// [TextElement.boundingBox] instead of discarding it into one flat
  /// string — [RecognizedText.blocks] → [TextBlock.lines] →
  /// [TextLine.elements] is already word-level, this just doesn't throw
  /// that structure away.
  ///
  /// Image dimensions are decoded separately since [RecognizedText] doesn't
  /// expose them, and the receipt NER model needs them to normalize boxes
  /// to its expected 0-1000 scale. Deliberately uses `package:image`'s
  /// [img.decodeImage] + [img.bakeOrientation] here, NOT `dart:ui`'s
  /// `instantiateImageCodec` — ML Kit's native `InputImage.fromFilePath`
  /// (what [InputImage.fromFile] calls into on Android) automatically
  /// applies the photo's EXIF orientation before detecting text, so
  /// [TextElement.boundingBox] values are already in the *display*
  /// (post-rotation) coordinate space. `instantiateImageCodec` ignores EXIF
  /// orientation entirely (a long-standing Skia/Flutter limitation) and
  /// reports the raw, pre-rotation dimensions — for any photo shot in
  /// portrait (the normal way to photograph a receipt), that's a 90°
  /// mismatch against ML Kit's boxes, with width/height often swapped, which
  /// silently corrupts every normalized bbox downstream. `bakeOrientation`
  /// (already relied on the same way inside [ImagePreprocessor]'s
  /// `copyResize` call, for the same EXIF reason) gives the correct
  /// post-rotation width/height to match ML Kit's space.
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
