import 'dart:async';

/// "지금 새로고침" 신호를 주고받는 곳.
///
/// 댓글을 쓰거나 알림을 읽음 처리하면, 해당 화면의 목록을 기다리지 않고 바로 다시 불러온다.
class RefreshHub {
  final _listeners = <String, Set<void Function()>>{};

  /// [key] 에 대한 새로고침 요청을 받을 함수를 등록한다. 해제 함수를 돌려준다.
  void Function() register(String key, void Function() onRefresh) {
    final set = _listeners.putIfAbsent(key, () => {});
    set.add(onRefresh);
    return () {
      set.remove(onRefresh);
      if (set.isEmpty) _listeners.remove(key);
    };
  }

  void refresh(String key) {
    for (final cb in List.of(_listeners[key] ?? const <void Function()>{})) {
      cb();
    }
  }
}

/// 처음 한 번 바로 불러오고, 이후 [interval] 마다 다시 불러오는 스트림.
///
/// - [hub] 에서 [key] 로 새로고침을 요청하면 즉시 다시 불러온다.
/// - 내용이 바뀌었을 때만 내보낸다 ([signature] 로 비교) → 화면이 쓸데없이 다시 그려지지 않음.
/// - 불러오는 중에 또 요청이 오면 겹쳐 부르지 않고, 끝난 뒤 한 번만 더 부른다.
/// - 아무도 듣지 않으면 타이머를 멈춘다 (화면을 나가면 요청도 멈춤).
Stream<T> pollingStream<T>({
  required Future<T> Function() load,
  required Duration interval,
  required RefreshHub hub,
  required String key,
  required String Function(T value) signature,
}) {
  late final StreamController<T> controller;
  Timer? timer;
  void Function()? unregister;
  var busy = false;
  var again = false;
  String? last;

  Future<void> tick() async {
    if (busy) {
      again = true;
      return;
    }
    busy = true;
    try {
      final value = await load();
      final sig = signature(value);
      if (sig != last && !controller.isClosed) {
        last = sig;
        controller.add(value);
      }
    } catch (e, st) {
      if (!controller.isClosed) controller.addError(e, st);
    } finally {
      busy = false;
      if (again && !controller.isClosed) {
        again = false;
        unawaited(tick());
      }
    }
  }

  controller = StreamController<T>(
    onListen: () {
      unawaited(tick());
      timer = Timer.periodic(interval, (_) => unawaited(tick()));
      unregister = hub.register(key, () => unawaited(tick()));
    },
    onCancel: () {
      timer?.cancel();
      unregister?.call();
    },
  );
  return controller.stream;
}
