/// Ignores a second tap on the same key for [window].
///
/// Use [allow] for instant toggles. Use [begin]/[end] when the first tap
/// starts an async write, so a second tap cannot race it.
class TapCooldown {
  TapCooldown({this.window = defaultWindow, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const Duration defaultWindow = Duration(seconds: 2);

  final Duration window;
  final DateTime Function() _clock;
  final Map<String, DateTime> _until = {};
  final Set<String> _busy = {};

  bool allow([String key = '']) {
    if (!_canStart(key)) return false;
    _arm(key);
    return true;
  }

  bool begin([String key = '']) {
    if (!_canStart(key)) return false;
    _arm(key);
    _busy.add(key);
    return true;
  }

  void end([String key = '']) {
    _busy.remove(key);
  }

  bool _canStart(String key) {
    if (_busy.contains(key)) return false;
    final until = _until[key];
    return until == null || !_clock().isBefore(until);
  }

  void _arm(String key) {
    _until[key] = _clock().add(window);
  }
}
