import 'package:image_picker/image_picker.dart';

/// Captures a receipt photo for OCR scanning (FR4.2). Wraps image_picker
/// rather than the lower-level `camera` plugin — a full custom camera
/// preview isn't needed here, just "take/pick a photo and get a file path".
class CameraService {
  final ImagePicker _picker = ImagePicker();

  /// Opens the device camera. Returns the captured photo's file path, or
  /// null if the user cancelled.
  Future<String?> captureReceiptPhoto() async {
    final photo = await _picker.pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 90);
    return photo?.path;
  }

  /// Lets the user pick an existing photo instead of using the camera.
  Future<String?> pickReceiptPhoto() async {
    final photo = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2000, imageQuality: 90);
    return photo?.path;
  }
}
