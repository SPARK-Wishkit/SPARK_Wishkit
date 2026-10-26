import { type AmplifyFunctionEvent, fieldNameOf } from '../shared/appsync-event';
import {
  isValidHttpUrl,
  isValidImageInput,
  toExtractedProduct,
  toIdentifiedTag,
  type EngineExtractResponse,
  type EngineIdentifyResponse,
  type ExtractedProduct,
  type IdentifiedTag,
} from './logic';

// backend.ts 가 넣어 주는 엔진 서버 내부 주소(예: http://<내부 ALB DNS>). VPC 안에서만
// 닿는 주소라 이 값 자체는 비밀이 아니다 — 실제 접근 통제는 보안그룹이 한다.
const ENGINE_BASE_URL = process.env.ENGINE_BASE_URL ?? '';

// ⚠️ AppSync 는 Lambda 리졸버를 30초까지만 기다린다(늘릴 수 없는 한도). 그보다 먼저 끊어야 앱이
// AppSync 의 알 수 없는 타임아웃 대신 ENGINE_TIMEOUT 을 받는다. 엔진 쪽 한도는 /extract 25초
// (EXTRACT_TIMEOUT_S — deploy/engine.sh 가 태스크 환경변수로 넣는다), /identify-tag 25초(IDENTIFY_TIMEOUT_S).
const FETCH_TIMEOUT_MS = 27_000;

/**
 * 앱이 구분해서 안내할 수 있게 오류는 이 코드 중 하나로만 던진다(메시지 = 코드).
 * 자세한 원인은 CloudWatch 로그에 남긴다. 앱 쪽 해석: lib/services/server_extract.dart.
 */
export const ErrorCode = {
  notConfigured: 'ENGINE_NOT_CONFIGURED', // 백엔드에 엔진 주소가 없음(ENGINE_DISABLED=1 배포)
  unavailable: 'ENGINE_UNAVAILABLE', // 엔진이 꺼져 있거나 연결 안 됨(engine.sh stop 상태 등)
  timeout: 'ENGINE_TIMEOUT', // 시간 안에 못 읽음
  failed: 'ENGINE_ERROR', // 엔진이 읽기에 실패(차단·렌더링 오류 등)
  invalidInput: 'INVALID_INPUT', // URL·사진 형식이 잘못됨
} as const;

// 이 함수 하나가 GraphQL 필드 두 개를 처리한다(VPC 연결 설정을 한 번만 하려고).
type Args =
  | { url: string }
  | { imageBase64: string; mimeType: string };

export const handler = async (
  event: AmplifyFunctionEvent<Args>,
): Promise<ExtractedProduct | IdentifiedTag> => {
  const fieldName = fieldNameOf(event);
  if (!ENGINE_BASE_URL) {
    throw new Error(ErrorCode.notConfigured);
  }
  switch (fieldName) {
    case 'identifyProductTag': {
      const { imageBase64, mimeType } = event.arguments as { imageBase64: string; mimeType: string };
      if (!isValidImageInput(imageBase64, mimeType)) {
        throw new Error(ErrorCode.invalidInput);
      }
      const body = await postToEngine<EngineIdentifyResponse>('/identify-tag', {
        image_base64: imageBase64,
        mime_type: mimeType,
      });
      return toIdentifiedTag(body);
    }
    case 'extractProduct': {
      const { url } = event.arguments as { url: string };
      if (!isValidHttpUrl(url)) {
        throw new Error(ErrorCode.invalidInput);
      }
      const body = await postToEngine<EngineExtractResponse>('/extract', { url });
      return toExtractedProduct(body);
    }
    default:
      // 원래는 모르는 필드도 /extract로 흘러갔다 — 스키마에 필드를 추가하고 여기를 빠뜨리면
      // 엉뚱한 호출 대신 바로 알아챌 수 있게 막는다.
      throw new Error(`Unknown field: ${fieldName}`);
  }
};

async function postToEngine<T>(path: string, payload: unknown): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  let resp: Response;
  try {
    resp = await fetch(`${ENGINE_BASE_URL}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
  } catch (exc) {
    clearTimeout(timeout);
    if (exc instanceof Error && exc.name === 'AbortError') throw new Error(ErrorCode.timeout);
    // 엔진이 꺼져 있으면 내부 주소(Cloud Map)가 안 풀리거나 연결이 거절된다 — fetch 가 TypeError 를 던진다.
    console.error(`[parsing-proxy] ${path} 연결 실패:`, exc);
    throw new Error(ErrorCode.unavailable);
  }
  try {
    if (!resp.ok) {
      const detail = await resp.text().catch(() => '');
      console.error(`[parsing-proxy] ${path} 엔진 오류 ${resp.status}: ${detail.slice(0, 500)}`);
      throw new Error(resp.status === 504 ? ErrorCode.timeout : ErrorCode.failed);
    }
    return (await resp.json()) as T;
  } catch (exc) {
    if (exc instanceof Error && exc.name === 'AbortError') throw new Error(ErrorCode.timeout);
    if (exc instanceof Error && Object.values<string>(ErrorCode).includes(exc.message)) throw exc;
    console.error(`[parsing-proxy] ${path} 응답 처리 실패:`, exc);
    throw new Error(ErrorCode.failed);
  } finally {
    clearTimeout(timeout);
  }
}
