import 'dart:ui';

import 'package:anpr/model/plate_result.dart';

abstract class AnprState {}

class AnprInitial extends AnprState {}

class AnprLoading extends AnprState {}

class ImagePicked extends AnprState {
  final String imagePath;
  ImagePicked(this.imagePath);
}

class AnprSuccess extends AnprState {
  final PlateResult result;
  AnprSuccess(this.result);
}

class AnprError extends AnprState {
  final String message;
  AnprError(this.message);
}

class AnprManualCrop extends AnprState {
  final String imagePath;
  final List<Offset> initialQuad;

  AnprManualCrop({required this.imagePath, required this.initialQuad});
}
