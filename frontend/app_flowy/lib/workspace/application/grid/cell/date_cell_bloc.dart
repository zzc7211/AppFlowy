import 'package:flowy_sdk/protobuf/flowy-grid-data-model/grid.pb.dart' show Field;
import 'package:flowy_sdk/protobuf/flowy-grid/date_type_option.pb.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'dart:async';
import 'cell_service/cell_service.dart';
part 'date_cell_bloc.freezed.dart';

class DateCellBloc extends Bloc<DateCellEvent, DateCellState> {
  final GridDateCellContext cellContext;
  void Function()? _onCellChangedFn;

  DateCellBloc({required this.cellContext}) : super(DateCellState.initial(cellContext)) {
    on<DateCellEvent>(
      (event, emit) async {
        event.when(
          initial: () => _startListening(),
          didReceiveCellUpdate: (DateCellData? cellData) {
            emit(state.copyWith(data: cellData, dateStr: _dateStrFromCellData(cellData)));
          },
          didReceiveFieldUpdate: (Field value) => emit(state.copyWith(field: value)),
        );
      },
    );
  }

  @override
  Future<void> close() async {
    if (_onCellChangedFn != null) {
      cellContext.removeListener(_onCellChangedFn!);
      _onCellChangedFn = null;
    }
    cellContext.dispose();
    return super.close();
  }

  void _startListening() {
    _onCellChangedFn = cellContext.startListening(
      onCellChanged: ((data) {
        if (!isClosed) {
          add(DateCellEvent.didReceiveCellUpdate(data));
        }
      }),
    );
  }
}

@freezed
class DateCellEvent with _$DateCellEvent {
  const factory DateCellEvent.initial() = _InitialCell;
  const factory DateCellEvent.didReceiveCellUpdate(DateCellData? data) = _DidReceiveCellUpdate;
  const factory DateCellEvent.didReceiveFieldUpdate(Field field) = _DidReceiveFieldUpdate;
}

@freezed
class DateCellState with _$DateCellState {
  const factory DateCellState({
    required DateCellData? data,
    required String dateStr,
    required Field field,
  }) = _DateCellState;

  factory DateCellState.initial(GridDateCellContext context) {
    final cellData = context.getCellData();

    return DateCellState(
      field: context.field,
      data: cellData,
      dateStr: _dateStrFromCellData(cellData),
    );
  }
}

String _dateStrFromCellData(DateCellData? cellData) {
  String dateStr = "";
  if (cellData != null) {
    dateStr = cellData.date + " " + cellData.time;
  }
  return dateStr;
}
