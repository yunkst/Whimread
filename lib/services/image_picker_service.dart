library;

import 'package:flutter/foundation.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

/// 图片过大异常（>10MB）。
class ImageTooLargeException implements Exception {
  final int actualBytes;
  final int maxBytes;
  const ImageTooLargeException(this.actualBytes, this.maxBytes);

  @override
  String toString() =>
      '图片过大：${actualBytes ~/ 1024 ~/ 1024}MB，上限 ${maxBytes ~/ 1024 ~/ 1024}MB';
}

/// 选图 + 裁剪封装服务。
///
/// 流程：相册选图（image_picker）→ 尺寸校验 → 自由裁剪（image_cropper）→ PNG bytes。
/// 任一步骤用户取消返回 null。图片 >10MB 抛 [ImageTooLargeException]。
class ImagePickerService {
  static const int maxBytes = 10 * 1024 * 1024; // 10MB

  /// 相册选图 + 自由裁剪。用户取消任一步骤返回 null。
  Future<Uint8List?> pickAndCrop() async {
    if (kIsWeb) return null;

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    if (picked == null) return null; // 用户在相册取消

    final Uint8List rawBytes = await picked.readAsBytes();
    validateSize(rawBytes);

    // 自由裁剪：不锁定比例，预设首项 original 为自由，另提供常用比例供切换。
    // image_cropper 8.x：aspectRatioPresets 移到 uiSettings 内；不传顶层 aspectRatio 即自由裁剪。
    final CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      compressFormat: ImageCompressFormat.png,
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪图片',
          lockAspectRatio: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
          cropStyle: CropStyle.rectangle,
        ),
        IOSUiSettings(
          title: '裁剪图片',
          aspectRatioLockEnabled: false,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio3x2,
            CropAspectRatioPreset.ratio4x3,
            CropAspectRatioPreset.ratio16x9,
          ],
          cropStyle: CropStyle.rectangle,
        ),
      ],
    );
    if (cropped == null) return null; // 用户在裁剪页取消

    return await cropped.readAsBytes();
  }

  /// 校验字节大小，超限抛 [ImageTooLargeException]。
  /// 抽成静态方法以便单测。
  static void validateSize(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw ImageTooLargeException(bytes.length, maxBytes);
    }
  }
}
