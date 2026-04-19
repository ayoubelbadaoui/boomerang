import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

/// Picks an image from [source] and opens a circular crop editor (Instagram/WhatsApp style).
/// Returns the cropped [File] or `null` if the user cancelled at any step.
Future<File?> pickAndCropAvatar(ImageSource source) async {
  final xFile = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 90,
  );
  if (xFile == null) return null;
  return cropAvatar(xFile.path);
}

/// Opens the circular crop editor on an already-picked image at [sourcePath].
/// Returns the cropped [File] or `null` if the user cancelled.
Future<File?> cropAvatar(String sourcePath) async {
  final cropped = await ImageCropper().cropImage(
    sourcePath: sourcePath,
    maxWidth: 512,
    maxHeight: 512,
    compressQuality: 90,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'Move and Scale',
        toolbarColor: Colors.black,
        toolbarWidgetColor: Colors.white,
        statusBarColor: Colors.black,
        backgroundColor: Colors.black,
        activeControlsWidgetColor: Colors.white,
        cropStyle: CropStyle.circle,
        hideBottomControls: false,
        lockAspectRatio: true,
        initAspectRatio: CropAspectRatioPreset.square,
        aspectRatioPresets: [CropAspectRatioPreset.square],
      ),
      IOSUiSettings(
        title: 'Move and Scale',
        cropStyle: CropStyle.circle,
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPickerButtonHidden: true,
        rotateButtonsHidden: true,
        rotateClockwiseButtonHidden: true,
      ),
    ],
  );
  if (cropped == null) return null;
  return File(cropped.path);
}
