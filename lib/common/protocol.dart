import 'dart:io';

import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

import 'print.dart';

const protocolSchemes = ['clash', 'clashmeta', 'flclash'];

bool canClaimProtocol(String currentHandler, String ownHandler) =>
    currentHandler.isEmpty || currentHandler == ownHandler;

class ProtocolRegistrationPlan {
  final String scheme;
  final String executable;

  const ProtocolRegistrationPlan({
    required this.scheme,
    required this.executable,
  });

  String get protocolKey => 'Software\\Classes\\$scheme';

  String get commandKey => 'shell\\open\\command';

  String get protocolValueName => 'URL Protocol';

  String get protocolValue => '';

  String get command => '"$executable" "%1"';
}

/// A user-level desktop entry for the running binary, including AppImages.
class LinuxProtocolRegistrationPlan {
  final List<String> schemes;
  final String executable;
  final String applicationsDir;

  const LinuxProtocolRegistrationPlan({
    required this.schemes,
    required this.executable,
    required this.applicationsDir,
  });

  String get desktopId => 'flclash-fork-url-handler.desktop';

  String get desktopPath => '$applicationsDir/$desktopId';

  List<String> get mimeTypes =>
      schemes.map((scheme) => 'x-scheme-handler/$scheme').toList();

  String get exec => '"${_quoteExecArgument(executable)}" %u';

  String get desktopEntry => [
    '[Desktop Entry]',
    'Type=Application',
    'Name=FlClash',
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

  void register(String scheme) {
    final plan = ProtocolRegistrationPlan(
      scheme: scheme,
      executable: Platform.resolvedExecutable,
    );
    try {
      final existing = CLASSES_ROOT.open('$scheme\\${plan.commandKey}');
      try {
        if ((existing.getString('') ?? '').isNotEmpty) return;
      } finally {
        existing.close();
      }
    } on WindowsException catch (error) {
      if (error.hr != ERROR_FILE_NOT_FOUND.toHRESULT() &&
          error.hr != ERROR_PATH_NOT_FOUND.toHRESULT()) {
        commonPrint.log('protocol registration lookup failed: $error');
        return;
      }
    }
    final regKey = CURRENT_USER.create(plan.protocolKey);
    try {
      regKey.setValue(
        plan.protocolValueName,
        RegistryValue.string(plan.protocolValue),
      );
      final commandKey = regKey.create(plan.commandKey);
      try {
        commandKey.setValue('', RegistryValue.string(plan.command));
      } finally {
        commandKey.close();
      }
    } finally {
      regKey.close();
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
