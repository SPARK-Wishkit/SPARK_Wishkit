import 'package:flutter_test/flutter_test.dart';
import 'package:figmadesign/utils/action_lock.dart';

void main() {
  test('second begin is ignored until end', () {
    final lock = ActionLock();

    expect(lock.begin('save'), isTrue);
    expect(lock.busy('save'), isTrue);
    expect(lock.begin('save'), isFalse);

    lock.end('save');
    expect(lock.busy('save'), isFalse);
    expect(lock.begin('save'), isTrue);
  });

  test('different keys do not block each other', () {
    final lock = ActionLock();
    expect(lock.begin('comment:a'), isTrue);
    expect(lock.begin('comment:b'), isTrue);
    expect(lock.begin('comment:a'), isFalse);
  });
}
