import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/auth/auth_validators.dart';

void main() {
  group('email', () {
    test('정상', () => expect(AuthValidators.email(' a@b.co '), isNull));
    test('빈 값', () => expect(AuthValidators.email(''), isNotNull));
    test('형식 오류', () => expect(AuthValidators.email('ab.co'), isNotNull));
    test('정규화', () {
      expect(AuthValidators.normalizeEmail('  Kim@Gmail.COM '), 'kim@gmail.com');
    });
  });

  group('password (서버 규칙: 8자 이상 + 숫자)', () {
    test('정상', () => expect(AuthValidators.password('wishkit1'), isNull));
    test('짧음', () => expect(AuthValidators.password('abc1'), isNotNull));
    test('숫자 없음', () => expect(AuthValidators.password('abcdefgh'), isNotNull));
    test('앞뒤 공백', () => expect(AuthValidators.password(' wishkit1'), isNotNull));
  });

  group('handle (pre-sign-up/handler.ts 와 같은 규칙)', () {
    test('정상', () {
      for (final h in ['abc', '@kim.ji_eun', 'a1b', 'x' * 20]) {
        expect(AuthValidators.handle(h), isNull, reason: h);
      }
    });
    test('거부', () {
      for (final h in ['', 'ab', 'x' * 21, '.abc', 'abc.', 'a..b', 'ab c!', '김지은']) {
        expect(AuthValidators.handle(h), isNotNull, reason: h);
      }
    });
    test('정규화: @ 붙이고 소문자', () {
      expect(AuthValidators.normalizeHandle(' @@Kim.Ji '), '@kim.ji');
      expect(AuthValidators.normalizeHandle('  '), '');
    });
  });

  group('code', () {
    test('6자리 숫자', () => expect(AuthValidators.code('012345'), isNull));
    test('자리수 틀림', () => expect(AuthValidators.code('1234'), isNotNull));
    test('문자 포함', () => expect(AuthValidators.code('12a456'), isNotNull));
  });

  test('maskEmail', () {
    expect(AuthValidators.maskEmail('kimjieun@gmail.com'), 'k***n@gmail.com');
    expect(AuthValidators.maskEmail('ab@x.com'), 'a*@x.com');
    expect(AuthValidators.maskEmail('broken'), '***');
  });
}
