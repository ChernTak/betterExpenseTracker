import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Resizes/normalizes a receipt photo into the fixed `pixel_values` tensor the on-device LayoutLMv3 NER model expects. Constants (incl. non-ImageNet mean/std [0.5,0.5,0.5]) and area-average resize match the real `LayoutLMv3ImageProcessor`; verified to produce identical argmax predictions to Python's exact pixels.
class ImagePreprocessor {
  static const int targetSize = 224;
  static const List<double> mean = [0.5, 0.5, 0.5];
  static const List<double> std = [0.5, 0.5, 0.5];

  /// Produces a flattened channel-first (C, H, W) float32 tensor matching the exported `.tflite` model's [1, 3, 224, 224] input signature.
  static Future<Float32List> preprocess(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    return preprocessBytes(bytes);
  }

  /// Same as [preprocess], from already-loaded bytes - split out so the
  /// core logic is testable without touching the filesystem.
  static Float32List preprocessBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw ArgumentError('Could not decode image (unrecognized format or corrupt data)');
    }

    final resized = img.copyResize(
      decoded,
      width: targetSize,
      height: targetSize,
      interpolation: img.Interpolation.average,
    );

    final output = Float32List(3 * targetSize * targetSize);
    var index = 0;
    for (var channel = 0; channel < 3; channel++) {
      for (var y = 0; y < targetSize; y++) {
        for (var x = 0; x < targetSize; x++) {
          final pixel = resized.getPixel(x, y);
          final rawValue = switch (channel) {
            0 => pixel.r.toDouble(),
            1 => pixel.g.toDouble(),
            _ => pixel.b.toDouble(),
          };
          final rescaled = rawValue / 255.0; // do_rescale: 0-255 -> 0-1
          output[index] = (rescaled - mean[channel]) / std[channel]; // do_normalize
          index++;
        }
      }
    }
    return output;
  }
}
