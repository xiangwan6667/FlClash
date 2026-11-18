import 'dart:io';

import 'package:rust_api/rust_api.dart' as rust_api;

import 'constant.dart';
import 'print.dart';

const protocolSchemes = ['clash', 'clashmeta', 'flclash'];

bool canClaimProtocol(String currentHandler, String ownHandler) =>
    currentHandler.isEmpty || currentHandler == ownHandler;

/// A user-level desktop entry that claims the schemes for the running binary,
/// so an AppImage or a development build is reachable without a packaged
/// .desktop file. Rewritten on every launch, like the Windows registry keys.
class LinuxProtocolRegistrationPlan {
  final List<String> schemes;
  final String executable;
  final String applicationsDir;

  const LinuxProtocolRegistrationPlan({
    required this.schemes,
    required this.executable,
    required this.applicationsDir,
  });

  String get desktopId => 'flclash-dev-url-handler.desktop';

  String get desktopPath => '$applicationsDir/$desktopId';

  List<String> get mimeTypes =>
      schemes.map((scheme) => 'x-scheme-handler/$scheme').toList();

  String get exec => '"${_quoteExecArgument(executable)}" %u';

  String get desktopEntry => [
    '[Desktop Entry]',
    'Type=Application',
    'Name=$appName',
    'NoDisplay=true',
    'Exec=$exec',
    'MimeType=${mimeTypes.join(';')};',
    '',
  ].join('\n');

  static String _quoteExecArgument(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll(r'$', r'\$')
        .replaceAll('`', r'\`')
        .replaceAll('%', '%%');
  }
}

class Protocol {
  static Protocol? _instance;

  Protocol._internal();

  factory Protocol() {
    _instance ??= Protocol._internal();
    return _instance!;
  }

  Future<void> registerWindows(List<String> schemes) async {
    for (final scheme in schemes) {
      final registered = await rust_api.registerUrlScheme(
        scheme: scheme,
        executable: Platform.resolvedExecutable,
      );
      if (!registered) {
        commonPrint.log('windows protocol registration failed: $scheme');
      }
    }
  }

  Future<void> registerLinux(List<String> schemes) async {
    final env = Platform.environment;
    final home = env['HOME'];
    if (home == null || home.isEmpty) {
      return;
    }
    final dataHome = env['XDG_DATA_HOME'];
    final plan = LinuxProtocolRegistrationPlan(
      schemes: schemes,
      executable: env['APPIMAGE'] ?? Platform.resolvedExecutable,
      applicationsDir:
          '${dataHome?.isNotEmpty == true ? dataHome : '$home/.local/share'}/applications',
    );
    try {
      final file = File(plan.desktopPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(plan.desktopEntry);
      final available = <String>[];
      for (final mimeType in plan.mimeTypes) {
        final query = await Process.run('xdg-mime', [
          'query',
          'default',
          mimeType,
        ]);
        if (query.exitCode != 0) {
          commonPrint.log('xdg-mime query failed: ${query.stderr}'.trim());
          continue;
        }
        final current = query.stdout.toString().trim();
        if (canClaimProtocol(current, plan.desktopId)) {
          available.add(mimeType);
        }
      }
      if (available.isEmpty) return;
      final result = await Process.run('xdg-mime', [
        'default',
        plan.desktopId,
        ...available,
      ]);
      if (result.exitCode != 0) {
        commonPrint.log('xdg-mime default failed: ${result.stderr}'.trim());
      }
    } catch (e) {
      commonPrint.log('linux protocol registration failed: $e');
    }
  }
}

final protocol = Protocol();
