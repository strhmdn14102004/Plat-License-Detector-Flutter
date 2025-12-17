import 'package:anpr/model/plate_result.dart';

abstract class HistoryState {}

class HistoryInitial extends HistoryState {}

class HistoryLoaded extends HistoryState {
  final List<PlateResult> history;
  HistoryLoaded(this.history);
}
