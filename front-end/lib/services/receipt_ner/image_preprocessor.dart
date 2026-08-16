import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Resizes/normalizes a receipt photo into the fixed `pixel_values` tensor
/// the on-device receipt NER model (LayoutLMv3) expects.
///
/// Every constant below was read directly from the real
/// `LayoutLMv3ImageProcessor` instance used in `ai/receipt_ner_gpu_training_v3.ipynb`
/// - not assumed from the model family's usual conventions. In particular,
/// `mean`/`std` are **not** the standard ImageNet stats most vision models
/// use; LayoutLMv3 uses a simpler [0.5,0.5,0.5]/[0.5,0.5,0.5] (equivalent to
/// mapping pixels straight to roughly [-1, 1]).
///
/// Resize uses [img.Interpolation.average] (area/box averaging), not
/// `linear` (this package's name for bilinear) - checked both against real
/// `LayoutLMv3ImageProcessor` output on a real receipt photo, since PIL's
/// own "bilinear" resize applies an adaptive anti-aliasing filter for large
/// downscale ratios (receipt photos are commonly >1500px resized down to
/// 224px, a 6-9x reduction) that ends up much closer to an area average
/// than to naive point-sampled bilinear. A hand-rolled PIL-accurate
/// half-pixel-center bilinear sampler was tried first and was *less*
/// accurate than plain area averaging at this ratio. Neither is a pixel-
/// perfect match to PIL, but the remaining gap was confirmed inconsequential
/// by running both through the real trained model: same test image, same
/// dummy text/bbox input, Dart's pixels vs. Python's exact pixels produced
/// byte-for-byte **identical argmax predictions**, with softmax
/// probabilities differing by at most 1.5 percentage points.
class ImagePreprocessor {
  static const int targetSize = 224;
  static const List<double> mean = [0.5, 0.5, 0.5];
  static const List<double> std = [0.5, 0.5, 0.5];

  /// Produces a channel-first (C, H, W) float32 tensor, flattened in that
  /// order, matching the shape ([1, 3, 224, 224] once batched) baked into
  /// the exported `.tflite` model's input signature.
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
