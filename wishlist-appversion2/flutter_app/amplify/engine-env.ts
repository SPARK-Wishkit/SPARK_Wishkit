import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

/**
 * 엔진 연결 설정(ENGINE_*) 읽기.
 *
 * Amplify 콘솔의 환경 변수는 빌드 셸에는 들어오지만, `ampx pipeline-deploy` 가 backend.ts 를 실행할 때는
 * 전달되지 않는다(2026-10-24 배포 로그: 셸에서 ENGINE_DISABLED=[1] 인데 backend.ts 에서는 비어 있음).
 * 그래서 amplify.yml 이 빌드 셸의 ENGINE_* 값을 amplify/.engine.env 로 써 두고, 여기서 읽는다.
 *
 * 우선순위: process.env(로컬 sandbox: `ENGINE_DISABLED=1 npx ampx sandbox …`) → .engine.env 파일(Amplify 빌드).
 */
const FILE_NAME = '.engine.env';

function candidatePaths(): string[] {
  const nextToThisFile = fileURLToPath(new URL(`./${FILE_NAME}`, import.meta.url));
  const fromWorkingDir = resolve(process.cwd(), 'amplify', FILE_NAME); // ampx 는 앱 폴더에서 실행된다
  return [...new Set([nextToThisFile, fromWorkingDir])];
}

/** `KEY=VALUE` 줄에서 ENGINE_ 로 시작하는 값만 뽑는다. 앞뒤 공백은 지운다. */
export function parseEngineEnv(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*(ENGINE_[A-Z0-9_]+)\s*=(.*)$/);
    if (m && m[2].trim()) out[m[1]] = m[2].trim();
  }
  return out;
}

function loadFile(): Record<string, string> {
  const path = candidatePaths().find((p) => existsSync(p));
  return path ? parseEngineEnv(readFileSync(path, 'utf8')) : {};
}

const fromFile = loadFile();

export function engineEnv(name: string): string | undefined {
  return process.env[name]?.trim() || fromFile[name] || undefined;
}
