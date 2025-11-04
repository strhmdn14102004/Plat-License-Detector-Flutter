import 'dart:typed_data';

abstract class PlateGalleryEvent {}

class PickGalleryImage extends PlateGalleryEvent {
  final Uint8List imageBytes;
  PickGalleryImage(this.imageBytes);
}
