import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/diary_theme.dart';

/// 살까말까를 어떻게 공유할지.
enum ShareMethod {
  /// 앱 친구에게 보내기 — 받은함·알림·댓글로 같이 고민한다.
  friends,

  /// 링크로 공유 — 카카오톡·인스타그램·문자 등으로 앱이 없는 사람에게도 보낸다.
  link,
}

/// "어떻게 공유할까요?" 선택창. 닫으면 null.
Future<ShareMethod?> pickShareMethod(BuildContext context) {
  return showModalBottomSheet<ShareMethod>(
    context: context,
    backgroundColor: DiaryColors.paper,
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          for (final (method, icon, title, subtitle) in const [
            (
              ShareMethod.friends,
              Icons.people_alt_outlined,
              '앱 친구에게 보내기',
              '친구가 댓글로 같이 고민해 줘요',
            ),
            (
              ShareMethod.link,
              Icons.link,
              '링크로 공유',
              '카카오톡·인스타그램 등으로 앱이 없는 친구에게도 보내요 (28일 동안 열려요)',
            ),
          ])
            ListTile(
              leading: Icon(icon, color: DiaryColors.ink),
              title: Text(title, style: DiaryTheme.body(15, weight: FontWeight.w700)),
              subtitle: Text(subtitle, style: DiaryTheme.body(12, color: DiaryColors.inkMuted)),
              onTap: () => Navigator.pop(sheetCtx, method),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// 공유창이 [context]의 위젯(버튼)을 가리키며 뜨게 할 위치. iPad에서만 쓰인다.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// 공유 페이지를 올리고([publish]가 주소를 돌려준다) 휴대폰 공유창을 띄운다.
///
/// 공유창을 못 띄우면(지원하지 않는 기기 등) 링크를 클립보드에 복사해 둔다.
/// 올리는 동안은 진행 표시를 띄워서 버튼을 두 번 누르지 못하게 한다.
Future<void> shareBasketLink({
  required BuildContext context,
  required Future<String> Function() publish,
  required String message,
  Rect? origin,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  final String url;
  try {
    url = await publish();
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(_errorText(e))));
    return;
  }
  navigator.pop();

  try {
    await SharePlus.instance.share(
      ShareParams(text: shareMessageText(message, url), subject: message, sharePositionOrigin: origin),
    );
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
    messenger.showSnackBar(
      const SnackBar(content: Text('공유창을 열 수 없어서 링크를 복사했어요. 원하는 곳에 붙여 넣어 주세요')),
    );
  }
}

/// 공유창에 넣는 글. 링크를 맨 끝 줄에 둬야 카카오톡 등이 미리보기 카드를 만든다.
String shareMessageText(String message, String url) => '${message.trim()}\n$url';

String _errorText(Object e) => e.toString().replaceFirst('Exception: ', '');
