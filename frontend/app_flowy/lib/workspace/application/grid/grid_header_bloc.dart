import 'package:app_flowy/workspace/application/grid/field/field_service.dart';
import 'package:flowy_sdk/log.dart';
import 'package:flowy_sdk/protobuf/flowy-grid-data-model/grid.pb.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'dart:async';
import 'grid_service.dart';

part 'grid_header_bloc.freezed.dart';

class GridHeaderBloc extends Bloc<GridHeaderEvent, GridHeaderState> {
  final GridFieldCache fieldCache;
  final String gridId;

  GridHeaderBloc({
    required this.gridId,
    required this.fieldCache,
  }) : super(GridHeaderState.initial(fieldCache.fields)) {
    on<GridHeaderEvent>(
      (event, emit) async {
        await event.map(
          initial: (_InitialHeader value) async {
            _startListening();
          },
          didReceiveFieldUpdate: (_DidReceiveFieldUpdate value) {
            emit(state.copyWith(fields: value.fields));
          },
          moveField: (_MoveField value) async {
            await _moveField(value, emit);
          },
        );
      },
    );
  }

  Future<void> _moveField(_MoveField value, Emitter<GridHeaderState> emit) async {
    final fields = List<Field>.from(state.fields);
    fields.insert(value.toIndex, fields.removeAt(value.fromIndex));
    emit(state.copyWith(fields: fields));

    final fieldService = FieldService(gridId: gridId, fieldId: value.field.id);
    final result = await fieldService.moveField(
      value.fromIndex,
      value.toIndex,
    );
    result.fold((l) {}, (err) => Log.error(err));
  }

  Future<void> _startListening() async {
    fieldCache.addListener(
      onChanged: (fields) => add(GridHeaderEvent.didReceiveFieldUpdate(fields)),
      listenWhen: () => !isClosed,
    );
  }

  @override
  Future<void> close() async {
    return super.close();
  }
}

@freezed
class GridHeaderEvent with _$GridHeaderEvent {
  const factory GridHeaderEvent.initial() = _InitialHeader;
  const factory GridHeaderEvent.didReceiveFieldUpdate(List<Field> fields) = _DidReceiveFieldUpdate;
  const factory GridHeaderEvent.moveField(Field field, int fromIndex, int toIndex) = _MoveField;
}

@freezed
class GridHeaderState with _$GridHeaderState {
  const factory GridHeaderState({required List<Field> fields}) = _GridHeaderState;

  factory GridHeaderState.initial(List<Field> fields) {
    // final List<Field> newFields = List.from(fields);
    // newFields.retainWhere((field) => field.visibility);
    return GridHeaderState(fields: fields);
  }
}
