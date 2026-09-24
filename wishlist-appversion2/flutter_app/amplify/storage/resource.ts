import { defineStorage } from '@aws-amplify/backend';

/**
 * 파일 저장소 (Amazon S3)
 *
 * 쓰기·지우기: 본인 폴더에만. ({entity_id} = 로그인한 사람의 Identity Pool ID)
 * 읽기: 앱과 공유 링크는 S3 에서 직접 읽지 않고 CloudFront(파일 배달망)로 읽는다.
 *       → 영구 주소가 생기고, 사진이 빨리 뜬다. (backend.ts 참고)
 *
 * 크기·형식 제한: 앱에서 검사한다. (프로필 사진 5MB, 리뷰 사진 8MB, 공유 페이지 1MB)
 */
export const storage = defineStorage({
  name: 'wishkitFiles',
  access: (allow) => ({
    'avatars/{entity_id}/*': [allow.entity('identity').to(['read', 'write', 'delete'])],
    'reviews/{entity_id}/*': [allow.entity('identity').to(['read', 'write', 'delete'])],
    'share-pages/{entity_id}/*': [allow.entity('identity').to(['read', 'write', 'delete'])],
  }),
});
