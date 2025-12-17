import 'dart:ui';

import 'package:image_picker/image_picker.dart';

abstract class AnprEvent {}

class PickImageEvent extends AnprEvent {
  final ImageSource source;
  PickImageEvent(this.source);
}

class ProcessImageEvent extends AnprEvent {
  final String imagePath;
  ProcessImageEvent(this.imagePath);
}

class ResetEvent extends AnprEvent {}

class SubmitManualCropEvent extends AnprEvent {
  final String imagePath;
  final List<Offset> quad;

  SubmitManualCropEvent({required this.imagePath, required this.quad});
}
