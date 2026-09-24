import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../data/app_store.dart';
import '../../models/models.dart';

/// Uploads the basket HTML snapshot, copies the public URL, and shows a snackbar.
Future<void> copyPublishedShareLink({
  required BuildContext context,
  required AppStore store,
  required SharedBasket basket,
}) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final url = await store.publishSharePage(basket);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('링크 복사됨 · 28일 동안 브라우저에서 열려 있어요'),
        action: SnackBarAction(
          label: '미리보기',
          onPressed: () => context.push('/shared/${basket.id}'),
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
    );
  }
}
