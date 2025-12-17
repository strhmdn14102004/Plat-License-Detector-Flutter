import 'package:anpr/model/plate_result.dart';
import 'package:anpr/module/history/history_anpr_event.dart';
import 'package:anpr/module/history/history_anpr_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class HistoryBloc extends Bloc<HistoryEvent, HistoryState> {
  final List<PlateResult> _history = [];

  HistoryBloc() : super(HistoryInitial()) {
    on<AddHistoryEvent>(_onAddHistory);
    on<ClearHistoryEvent>(_onClearHistory);
  }

  void _onAddHistory(AddHistoryEvent event, Emitter<HistoryState> emit) {
    _history.insert(0, event.result);
    emit(HistoryLoaded(List.from(_history)));
  }

  void _onClearHistory(ClearHistoryEvent event, Emitter<HistoryState> emit) {
    _history.clear();
    emit(HistoryLoaded([]));
  }
}
