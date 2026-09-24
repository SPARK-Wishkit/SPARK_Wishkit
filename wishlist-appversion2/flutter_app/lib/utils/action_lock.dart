/// Blocks a second call with the same [key] until [end] runs.
///
/// Unlike a cooldown, the next tap is allowed as soon as the first write
/// finishes.
class ActionLock {
  final Set<String> _busy = {};

  bool busy([String key = '']) => _busy.contains(key);

  bool begin([String key = '']) {
    if (_busy.contains(key)) return false;
    _busy.add(key);
    return true;
  }

  void end([String key = '']) {
    _busy.remove(key);
  }
}
