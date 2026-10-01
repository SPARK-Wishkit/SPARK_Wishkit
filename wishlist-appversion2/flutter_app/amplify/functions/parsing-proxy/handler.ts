import type { AppSyncResolverHandler } from 'aws-lambda';
import { isValidHttpUrl, toExtractedProduct, type EngineExtractResponse, type ExtractedProduct } from './logic';

// backend.ts 가 넣어 주는 엔진 서버 내부 주소(예: http://<내부 ALB DNS>). VPC 안에서만
// 닿는 주소라 이 값 자체는 비밀이 아니다 — 실제 접근 통제는 보안그룹이 한다.
const ENGINE_BASE_URL = process.env.ENGINE_BASE_URL ?? '';

// 엔진 서버 자체 타임아웃(45초)보다 여유를 주되, 이 함수의 timeoutSeconds(60, resource.ts)
// 보다는 짧게 잡아서 Lambda가 강제 종료되기 전에 정상적인 에러 메시지를 돌려준다.
const FETCH_TIMEOUT_MS = 55_000;

type Args = { url: string };

export const handler: AppSyncResolverHandler<Args, ExtractedProduct> = async (event) => {
  const url = event.arguments.url;
  if (!isValidHttpUrl(url)) {
    throw new Error('유효하지 않은 URL입니다.');
  }
  if (!ENGINE_BASE_URL) {
    throw new Error('엔진 서버 주소가 설정되지 않았습니다(ENGINE_BASE_URL 환경변수 확인).');
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const resp = await fetch(`${ENGINE_BASE_URL}/extract`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ url }),
      signal: controller.signal,
    });
    if (!resp.ok) {
      const detail = await resp.text().catch(() => '');
      throw new Error(`엔진 서버 오류(${resp.status}): ${detail}`);
    }
    const body = (await resp.json()) as EngineExtractResponse;
    return toExtractedProduct(body);
  } catch (exc) {
    if (exc instanceof Error && exc.name === 'AbortError') {
      throw new Error('엔진 서버 응답이 너무 오래 걸려 취소되었습니다.');
    }
    throw exc;
  } finally {
    clearTimeout(timeout);
  }
};
