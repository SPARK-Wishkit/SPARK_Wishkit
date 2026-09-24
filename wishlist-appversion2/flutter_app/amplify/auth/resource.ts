import { defineAuth } from '@aws-amplify/backend';
import { preSignUp } from './pre-sign-up/resource';

/**
 * wishkit 로그인(Cognito) 설정.
 *
 * - 이메일 + 비밀번호로 로그인
 * - 이메일 인증은 6자리 코드
 * - 가입 때 받은 이름/아이디는 Cognito 속성(name, preferred_username)에
 *   "가입 초안"으로만 담아 둔다. 아이디 중복 검사와 최종 원본은
 *   앱 데이터 쪽 프로필이 맡는다. → TEAM_CONTRACT.md 참고
 * - 비밀번호 규칙과 토큰 수명은 ../backend.ts 에서 덮어쓴다.
 */
export const auth = defineAuth({
  loginWith: {
    email: {
      verificationEmailStyle: 'CODE',
      verificationEmailSubject: '[wishkit] 이메일 인증 코드',
      verificationEmailBody: (createCode) =>
        `wishkit 인증 코드는 ${createCode()} 입니다. 앱에 입력해 주세요.`,
    },
  },
  userAttributes: {
    fullname: { required: false, mutable: true },
    preferredUsername: { required: false, mutable: true },
  },
  accountRecovery: 'EMAIL_ONLY',
  triggers: {
    preSignUp,
  },
});
