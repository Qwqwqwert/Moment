import 'dart:io';

enum MomentPlatformKind { android, windows, linux, other }

/// Centralizes platform capabilities used by application services and widgets.
class MomentPlatform {
  const MomentPlatform._();

  static MomentPlatformKind get kind {
    if (Platform.isAndroid) return MomentPlatformKind.android;
    if (Platform.isWindows) return MomentPlatformKind.windows;
    if (Platform.isLinux) return MomentPlatformKind.linux;
    return MomentPlatformKind.other;
  }

  static bool get isDesktop =>
      kind == MomentPlatformKind.windows || kind == MomentPlatformKind.linux;

  static bool get isWindows => kind == MomentPlatformKind.windows;
  static bool get isLinux => kind == MomentPlatformKind.linux;
  static bool get isAndroid => kind == MomentPlatformKind.android;

  static bool get supportsRuntimeReminders => isDesktop;
  static bool get supportsCameraCapture => !isDesktop;

  static String get notificationSettingsHelp => isLinux
      ? '请在 Ubuntu“设置 > 通知”中允许 Moment，并检查勿扰模式。退出 Moment 后不会提醒。'
      : isWindows
      ? '请在 Windows“通知”设置中允许 Moment，并检查勿扰模式。退出 Moment 后不会提醒。'
      : '请在系统设置中允许 Moment 的通知权限。';
}
