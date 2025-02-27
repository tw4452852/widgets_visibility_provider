import 'dart:async';
import 'dart:collection';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:widgets_visibility_provider/src/visible_notifier_widget.dart';

class WidgetsVisibilityProviderBloc extends Bloc<
    MapEntry<ScrollNotification?, Iterable<MapEntry<Key, PositionData>>>,
    WidgetsVisibilityEvent> {
  WidgetsVisibilityProviderBloc({
    this.condition,
  }) : super(const WidgetsVisibilityFullEvent());

  final bool Function(PositionData positionData)? condition;
  final Map<Element, dynamic> _elementMap = <Element, dynamic>{};

  bool _updateScheduling = false;
  bool _waitUpdateScheduled = false;
  ScrollNotification? _lastNotification;

  @override
  Stream<WidgetsVisibilityEvent> mapEventToState(
      MapEntry<ScrollNotification?, Iterable<MapEntry<Key, PositionData>>>
          mapEntry) async* {
    var positionDataMap = LinkedHashMap.fromEntries(
      mapEntry.value.toList()
        ..sort(
          (a, b) => a.value.startPosition.compareTo(b.value.startPosition),
        ),
    );
    yield WidgetsVisibilityFullEvent(
      notification: mapEntry.key,
      positionDataMap: positionDataMap,
      positionDataList: positionDataMap.values.toList(),
    );
  }

  @mustCallSuper
  void _addElement(SenderElement element, dynamic data) {
    _elementMap[element] = data;
    _schedulePositionUpdate();
  }

  @mustCallSuper
  void _removeElement(SenderElement element) {
    _elementMap.remove(element);
    _schedulePositionUpdate();
  }

  void _schedulePositionUpdate([ScrollNotification? notification]) {
    _lastNotification = notification ?? _lastNotification;

    _waitUpdateScheduled = true;
    if (!_updateScheduling) {
      _updateScheduling = true;
      _waitUpdateScheduled = false;
      SchedulerBinding.instance!.addPostFrameCallback(
        (_) {
          if (_elementMap.isEmpty) return;
          RenderViewport? viewport;

          var iterable = _elementMap.entries.map((e) {
            var element = e.key;
            dynamic value = e.value;

            if (element.dirty) return null;

            try {
              var renderObject = element.renderObject;
              assert(renderObject != null);
              assert(renderObject is RenderBox);
              final box = renderObject as RenderBox;
              var renderAbstractViewport = RenderAbstractViewport.of(box);
              assert(renderAbstractViewport != null);
              assert(renderAbstractViewport is RenderViewport);
              viewport ??= renderAbstractViewport as RenderViewport;
              assert(viewport != null);

              var offsetToReveal = viewport!.getOffsetToReveal(box, 0);
              final reveal = offsetToReveal.offset;
              var start = reveal - viewport!.offset.pixels;

              var vertical = viewport!.axis == Axis.vertical;
              var itemSize = vertical
                  ? offsetToReveal.rect.size.height
                  : offsetToReveal.rect.size.width;

              var viewportSize =
                  vertical ? viewport!.size.height : viewport!.size.width;

              var end = start + itemSize;

              return MapEntry(
                element.widget.key,
                PositionData(
                  startPosition: start,
                  endPosition: end,
                  viewportSize: viewportSize,
                  data: value,
                ),
              );
            } catch (_) {}

            return null;
          }).where((mapEntry) {
            if (mapEntry == null || mapEntry.key == null) return false;
            return condition?.call(mapEntry.value) ??
                mapEntry.value.endPosition > 0 &&
                    mapEntry.value.startPosition < mapEntry.value.viewportSize;
          });

          add(MapEntry(_lastNotification,
              iterable as Iterable<MapEntry<Key, PositionData>>));

          _updateScheduling = false;
          if (_waitUpdateScheduled) _schedulePositionUpdate();
        },
      );
    }
  }
}

class WidgetsVisibilityProvider extends StatelessWidget {
  final bool Function(PositionData positionData)? condition;
  final Widget child;

  const WidgetsVisibilityProvider({
    Key? key,
    this.condition,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider<WidgetsVisibilityProviderBloc>(
      create: (context) => WidgetsVisibilityProviderBloc(
        condition: condition,
      ),
      child: Builder(
        builder: (context) => NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification notification) {
            BlocProvider.of<WidgetsVisibilityProviderBloc>(context)
                ._schedulePositionUpdate(notification);
            return false;
          },
          child: child,
        ),
      ),
    );
  }
}

class SenderElement extends ProxyElement {
  SenderElement(ProxyWidget widget) : super(widget);

  @override
  void notifyClients(ProxyWidget oldWidget) {}

  RenderViewport? get viewport =>
      RenderAbstractViewport.of(renderObject) as RenderViewport?;

  RenderBox? get renderBox => renderObject as RenderBox?;

  WidgetsVisibilityProviderBloc? _bloc;

  @override
  void mount(Element? parent, dynamic newSlot) {
    super.mount(parent, newSlot);
    (_bloc ??= BlocProvider.of<WidgetsVisibilityProviderBloc>(this))
        ._addElement(this, (widget as SenderWidget).data);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    (_bloc ??= BlocProvider.of<WidgetsVisibilityProviderBloc>(this))
        ._addElement(this, (widget as SenderWidget).data);
  }

  @override
  void unmount() {
    _bloc?._removeElement(this);
    super.unmount();
  }
}

class WidgetsVisibilityFullEvent extends WidgetsVisibilityEvent {
  final Map<Key, PositionData> positionDataMap;

  const WidgetsVisibilityFullEvent({
    ScrollNotification? notification,
    List<PositionData> positionDataList = const [],
    this.positionDataMap = const {},
  }) : super(notification: notification, positionDataList: positionDataList);

  @override
  List<Object?> get props => [
        notification,
        positionDataList,
        positionDataMap,
      ];
}

class WidgetsVisibilityEvent extends Equatable {
  final ScrollNotification? notification;
  final List<PositionData> positionDataList;

  const WidgetsVisibilityEvent({
    this.notification,
    required this.positionDataList,
  });

  @override
  List<Object?> get props => [
        notification,
        positionDataList,
      ];

  @override
  bool? get stringify => true;
}

class PositionData extends Equatable {
  final double startPosition;
  final double endPosition;
  final double viewportSize;
  final dynamic data;

  PositionData({
    required this.startPosition,
    required this.endPosition,
    required this.viewportSize,
    required this.data,
  });

  @override
  List<Object> get props => [startPosition, endPosition, viewportSize, data];

  @override
  bool get stringify => true;
}
