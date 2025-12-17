import 'package:anpr/model/plate_result.dart';

abstract class HistoryEvent {}

class AddHistoryEvent extends HistoryEvent {
  final PlateResult result;
  AddHistoryEvent(this.result);
}

class ClearHistoryEvent extends HistoryEvent {}
