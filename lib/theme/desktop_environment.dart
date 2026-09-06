import 'package:flutter/material.dart';

enum DesktopModule { notes, todos }

class DesktopEnvironment extends InheritedWidget {
  const DesktopEnvironment({
    super.key,
    required this.isDesktop,
    required this.module,
    required this.switchModule,
    required this.openInWorkspace,
    required super.child,
  });

  const DesktopEnvironment.mobile({super.key, required super.child})
    : isDesktop = false,
      module = DesktopModule.notes,
      switchModule = _noopSwitch,
      openInWorkspace = _noopOpen;

  final bool isDesktop;
  final DesktopModule module;
  final ValueChanged<DesktopModule> switchModule;
  final ValueChanged<Widget> openInWorkspace;

  static bool isDesktopOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<DesktopEnvironment>()
          ?.isDesktop ??
      false;

  static DesktopEnvironment? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopEnvironment>();

  @override
  bool updateShouldNotify(DesktopEnvironment oldWidget) =>
      isDesktop != oldWidget.isDesktop || module != oldWidget.module;

  static void _noopSwitch(DesktopModule _) {}
  static void _noopOpen(Widget _) {}
}
