import 'package:flutter_test/flutter_test.dart';
import 'package:figmadesign/utils/tap_cooldown.dart';

void main() {
  test('second tap inside the window is ignored', () {
    var now = DateTime(2026, 8, 22, 18);
    final cooldown = TapCooldown(clock: () => now);

    expect(cooldown.allow('save'), isTrue);
    expect(cooldown.allow('save'), isFalse);

    now = now.add(const Duration(milliseconds: 1999));
    expect(cooldown.allow('save'), isFalse);

    now = now.add(const Duration(milliseconds: 1));
    expect(cooldown.allow('save'), isTrue);
  });

  test('different keys do not block each other', () {
    final cooldown = TapCooldown(clock: () => DateTime(2026, 8, 22));
    expect(cooldown.allow('follow:a'), isTrue);
    expect(cooldown.allow('follow:b'), isTrue);
    expect(cooldown.allow('follow:a'), isFalse);
  });

  test('begin blocks until end even after the window', () async {
    var now = DateTime(2026, 8, 22, 18);
    final cooldown = TapCooldown(clock: () => now);

    expect(cooldown.begin('follow'), isTrue);
    now = now.add(const Duration(seconds: 5));
    expect(cooldown.begin('follow'), isFalse);

    cooldown.end('follow');
    expect(cooldown.begin('follow'), isTrue);
  });
}
