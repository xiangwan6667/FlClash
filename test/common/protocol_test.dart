import 'package:fl_clash/common/protocol.dart';
import 'package:test/test.dart';

void main() {
  group('LinuxProtocolRegistrationPlan', () {
    const plan = LinuxProtocolRegistrationPlan(
      schemes: protocolSchemes,
      executable: '/home/me/Apps/FlClash.AppImage',
      applicationsDir: '/home/me/.local/share/applications',
    );

    test('writes a hidden desktop entry claiming every scheme', () {
      expect(
        plan.desktopPath,
        '/home/me/.local/share/applications/flclash-rs-url-handler.desktop',
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

    test('preserves an existing protocol handler', () {
      expect(canClaimProtocol('', plan.desktopId), isTrue);
      expect(canClaimProtocol(plan.desktopId, plan.desktopId), isTrue);
      expect(canClaimProtocol('upstream.desktop', plan.desktopId), isFalse);
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
