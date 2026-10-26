/// Built-in DiceBear thumbs avatars for profile picker.
class AvatarPresets {
  AvatarPresets._();

  static const _style = 'thumbs';

  /// Five fixed seeds so the choices stay the same for everyone.
  static const seeds = ['wishkit', 'peach', 'mint', 'stone', 'coral'];

  static List<String> get urls => [
        for (final seed in seeds) urlForSeed(seed),
      ];

  static String urlForSeed(String seed) =>
      'https://api.dicebear.com/7.x/$_style/png?seed=${Uri.encodeComponent(seed)}';

  static bool isPreset(String url) => urls.contains(url);
}
