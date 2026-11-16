import 'dart:io';

import 'package:fl_clash/common/protocol.dart';
import 'package:test/test.dart';
import 'package:win32_registry/win32_registry.dart';

void main() {
  group('ProtocolRegistrationPlan', () {
    test('builds registry writes for URL protocol registration', () {
      const plan = ProtocolRegistrationPlan(
        scheme: 'flclash',
        executable: r'C:\Program Files\FlClash\FlClash.exe',
      );

      expect(plan.protocolKey, r'Software\Classes\flclash');
      expect(plan.commandKey, r'shell\open\command');
      expect(plan.protocolValueName, 'URL Protocol');
      expect(plan.protocolValue, '');
      expect(plan.command, r'"C:\Program Files\FlClash\FlClash.exe" "%1"');
    });
  });

  test('Windows registration preserves an existing handler', () {
    final scheme = 'flclash-test-$pid-${DateTime.now().microsecondsSinceEpoch}';
    final root = CURRENT_USER.create(r'Software\Classes');
    addTearDown(() {
      root.removeSubkey(scheme);
      root.close();
    });

    const existing = r'"C:\Other App\FlClash.exe" "%1"';
    final command = root.create('$scheme\\shell\\open\\command');
    command.setValue('', const RegistryValue.string(existing));
    command.close();

    Protocol().register(scheme);

    final registered = root.open('$scheme\\shell\\open\\command');
    expect(registered.getString(''), existing);
    registered.close();
  }, skip: !Platform.isWindows);

  test('Windows registration creates an unused handler', () {
    final scheme = 'flclash-test-$pid-${DateTime.now().microsecondsSinceEpoch}';
    final root = CURRENT_USER.create(r'Software\Classes');
    addTearDown(() {
      root.removeSubkey(scheme);
      root.close();
    });

    Protocol().register(scheme);

    final registered = root.open('$scheme\\shell\\open\\command');
    expect(registered.getString(''), '"${Platform.resolvedExecutable}" "%1"');
    registered.close();
  }, skip: !Platform.isWindows);

  group('LinuxProtocolRegistrationPlan', () {
    const plan = LinuxProtocolRegistrationPlan(
      schemes: protocolSchemes,
      executable: '/home/me/Apps/FlClash.AppImage',
      applicationsDir: '/home/me/.local/share/applications',
    );

    test('writes a hidden desktop entry claiming every scheme', () {
      expect(
        plan.desktopPath,
        '/home/me/.local/share/applications/flclash-fork-url-handler.desktop',
      );
      expect(
        plan.desktopEntry,
        '[Desktop Entry]\n'
        'Type=Application\n'
        'Name=FlClash\n'
        'NoDisplay=true\n'
        'Exec="/home/me/Apps/FlClash.AppImage" %u\n'
        'MimeType=x-scheme-handler/clash;x-scheme-handler/clashmeta;'
        'x-scheme-handler/flclash;\n',
      );
    });

    test('leaves another application as the default handler', () {
      expect(canClaimProtocol('', plan.desktopId), isTrue);
      expect(canClaimProtocol(plan.desktopId, plan.desktopId), isTrue);
      expect(
        canClaimProtocol('flclash-url-handler.desktop', plan.desktopId),
        isFalse,
      );
    });

    test('escapes reserved characters in the executable path', () {
      const plan = LinuxProtocolRegistrationPlan(
        schemes: ['flclash'],
        executable: r'/opt/my "apps"/$HOME/100%/Fl`Clash\bin',
        applicationsDir: '/tmp',
      );

      expect(plan.exec, r'"/opt/my \"apps\"/\$HOME/100%%/Fl\`Clash\\bin" %u');
    });
  });
}
