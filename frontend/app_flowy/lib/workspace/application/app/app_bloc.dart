import 'dart:collection';

import 'package:app_flowy/plugin/plugin.dart';
import 'package:app_flowy/startup/startup.dart';
import 'package:app_flowy/workspace/application/app/app_listener.dart';
import 'package:app_flowy/workspace/application/app/app_service.dart';
import 'package:app_flowy/workspace/presentation/home/menu/menu.dart';
import 'package:expandable/expandable.dart';
import 'package:flowy_sdk/log.dart';
import 'package:flowy_sdk/protobuf/flowy-folder-data-model/app.pb.dart';
import 'package:flowy_sdk/protobuf/flowy-folder-data-model/view.pb.dart';
import 'package:flowy_sdk/protobuf/flowy-error/errors.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartz/dartz.dart';

part 'app_bloc.freezed.dart';

class AppBloc extends Bloc<AppEvent, AppState> {
  final App app;
  final AppService appService;
  final AppListener appListener;

  AppBloc({required this.app, required this.appService, required this.appListener}) : super(AppState.initial(app)) {
    on<AppEvent>((event, emit) async {
      await event.map(initial: (e) async {
        _startListening();
        await _loadViews(emit);
      }, createView: (CreateView value) async {
        await _createView(value, emit);
      }, didReceiveViewUpdated: (e) async {
        await _didReceiveViewUpdated(e.views, emit);
      }, delete: (e) async {
        await _deleteView(emit);
      }, rename: (e) async {
        await _renameView(e, emit);
      }, appDidUpdate: (e) async {
        emit(state.copyWith(app: e.app));
      });
    });
  }

  void _startListening() {
    appListener.start(
      onViewsChanged: (result) {
        result.fold(
          (views) {
            if (!isClosed) {
              add(AppEvent.didReceiveViewUpdated(views));
            }
          },
          (error) => Log.error(error),
        );
      },
      onAppUpdated: (app) {
        if (!isClosed) {
          add(AppEvent.appDidUpdate(app));
        }
      },
    );
  }

  Future<void> _renameView(Rename e, Emitter<AppState> emit) async {
    final result = await appService.updateApp(appId: app.id, name: e.newName);
    result.fold(
      (l) => emit(state.copyWith(successOrFailure: left(unit))),
      (error) => emit(state.copyWith(successOrFailure: right(error))),
    );
  }

  Future<void> _deleteView(Emitter<AppState> emit) async {
    final result = await appService.delete(appId: app.id);
    result.fold(
      (unit) => emit(state.copyWith(successOrFailure: left(unit))),
      (error) => emit(state.copyWith(successOrFailure: right(error))),
    );
  }

  Future<void> _createView(CreateView value, Emitter<AppState> emit) async {
    final viewOrFailed = await appService.createView(
      appId: app.id,
      name: value.name,
      desc: value.desc,
      dataType: value.dataType,
      pluginType: value.pluginType,
    );
    viewOrFailed.fold(
      (view) => emit(state.copyWith(
        latestCreatedView: view,
        successOrFailure: left(unit),
      )),
      (error) {
        Log.error(error);
        emit(state.copyWith(successOrFailure: right(error)));
      },
    );
  }

  @override
  Future<void> close() async {
    await appListener.stop();
    return super.close();
  }

  Future<void> _didReceiveViewUpdated(List<View> views, Emitter<AppState> emit) async {
    final latestCreatedView = state.latestCreatedView;
    AppState newState = state.copyWith(views: views);
    if (latestCreatedView != null) {
      final index = views.indexWhere((element) => element.id == latestCreatedView.id);
      if (index == -1) {
        newState = newState.copyWith(latestCreatedView: null);
      }
    }

    emit(newState);
  }

  Future<void> _loadViews(Emitter<AppState> emit) async {
    final viewsOrFailed = await appService.getViews(appId: app.id);
    viewsOrFailed.fold(
      (views) => emit(state.copyWith(views: views)),
      (error) {
        Log.error(error);
        emit(state.copyWith(successOrFailure: right(error)));
      },
    );
  }
}

@freezed
class AppEvent with _$AppEvent {
  const factory AppEvent.initial() = Initial;
  const factory AppEvent.createView(
    String name,
    String desc,
    PluginDataType dataType,
    PluginType pluginType,
  ) = CreateView;
  const factory AppEvent.delete() = Delete;
  const factory AppEvent.rename(String newName) = Rename;
  const factory AppEvent.didReceiveViewUpdated(List<View> views) = ReceiveViews;
  const factory AppEvent.appDidUpdate(App app) = AppDidUpdate;
}

@freezed
class AppState with _$AppState {
  const factory AppState({
    required App app,
    required List<View> views,
    View? latestCreatedView,
    required Either<Unit, FlowyError> successOrFailure,
  }) = _AppState;

  factory AppState.initial(App app) => AppState(
        app: app,
        views: [],
        successOrFailure: left(unit),
      );
}

class AppViewDataContext extends ChangeNotifier {
  final String appId;
  final ValueNotifier<List<View>> _viewsNotifier = ValueNotifier([]);
  final ValueNotifier<View?> _selectedViewNotifier = ValueNotifier(null);
  VoidCallback? _menuSharedStateListener;
  ExpandableController expandController = ExpandableController(initialExpanded: false);

  AppViewDataContext({required this.appId}) {
    _setLatestView(getIt<MenuSharedState>().latestOpenView);
    _menuSharedStateListener = getIt<MenuSharedState>().addLatestViewListener((view) {
      _setLatestView(view);
    });
  }

  VoidCallback addSelectedViewChangeListener(void Function(View?) callback) {
    listener() {
      callback(_selectedViewNotifier.value);
    }

    _selectedViewNotifier.addListener(listener);
    return listener;
  }

  void removeSelectedViewListener(VoidCallback listener) {
    _selectedViewNotifier.removeListener(listener);
  }

  void _setLatestView(View? view) {
    view?.freeze();

    if (_selectedViewNotifier.value != view) {
      _selectedViewNotifier.value = view;
      _expandIfNeed();
      notifyListeners();
    }
  }

  View? get selectedView => _selectedViewNotifier.value;

  set views(List<View> views) {
    if (_viewsNotifier.value != views) {
      _viewsNotifier.value = views;
      _expandIfNeed();
      notifyListeners();
    }
  }

  UnmodifiableListView<View> get views => UnmodifiableListView(_viewsNotifier.value);

  VoidCallback addViewsChangeListener(void Function(UnmodifiableListView<View>) callback) {
    listener() {
      callback(views);
    }

    _viewsNotifier.addListener(listener);
    return listener;
  }

  void removeViewsListener(VoidCallback listener) {
    _viewsNotifier.removeListener(listener);
  }

  void _expandIfNeed() {
    if (_selectedViewNotifier.value == null) {
      return;
    }

    if (!_viewsNotifier.value.contains(_selectedViewNotifier.value)) {
      return;
    }

    if (expandController.expanded == false) {
      // Workaround: Delay 150 milliseconds to make the smooth animation while expanding
      Future.delayed(const Duration(milliseconds: 150), () {
        expandController.expanded = true;
      });
    }
  }

  @override
  void dispose() {
    if (_menuSharedStateListener != null) {
      getIt<MenuSharedState>().removeLatestViewListener(_menuSharedStateListener!);
    }
    super.dispose();
  }
}
