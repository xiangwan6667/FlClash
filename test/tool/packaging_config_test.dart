import 'dart:io';

import 'package:fl_clash/models/clash_config.dart' show defaultTunDevice;
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('uses an independent identity across desktop and Android', () {
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    final linux = File('linux/CMakeLists.txt').readAsStringSync();
    final macos = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final windows =
        loadYaml(
              File('windows/packaging/exe/make_config.yaml').readAsStringSync(),
            )
            as YamlMap;

    expect(android, contains('applicationId = "app.flclash.fork"'));
    expect(linux, contains('set(APPLICATION_ID "app.flclash.fork")'));
    expect(macos, contains('PRODUCT_BUNDLE_IDENTIFIER = app.flclash.fork'));
    expect(windows['display_name'], 'FlClash');
    expect(windows['install_dir_name'], r'{autopf64}\FlClash-Fork');
    expect(
      windows['app_id'],
      isNot(
        anyOf(
          '728B3532-C74B-4870-9068-BE70FE12A3E6',
          'A26EF02E-3646-477E-BB8D-A36BC9A49755',
        ),
      ),
    );
    expect(defaultTunDevice.length, lessThanOrEqualTo(15));
  });

  group('Linux packaging teardown', () {
    for (final format in ['deb', 'rpm']) {
      test('$format removes the Helper unit only on a real uninstall', () {
        final config =
            loadYaml(
                  File(
                    'linux/packaging/$format/make_config.yaml',
                  ).readAsStringSync(),
                )
                as YamlMap;
        final scripts = (config['postuninstall_scripts'] as YamlList)
            .cast<String>();

        expect(scripts.first, contains('exit 0'));
        expect(
          scripts,
          contains('rm -f /etc/systemd/system/flclash-fork-helper.service'),
        );
        expect(
          scripts.any((script) => script.contains('systemctl daemon-reload')),
          isTrue,
        );
      });
    }
  });

  test('every Linux package names the GTK application id as its window '
      'class', () {
    final applicationId = RegExp(
      r'set\(APPLICATION_ID "([^"]+)"\)',
    ).firstMatch(File('linux/CMakeLists.txt').readAsStringSync())!.group(1);

    for (final format in ['deb', 'rpm', 'appimage']) {
      final config =
          loadYaml(
                File(
                  'linux/packaging/$format/make_config.yaml',
                ).readAsStringSync(),
              )
              as YamlMap;
      expect(config['startup_wm_class'], applicationId, reason: format);
    }
  });

  test('rpm keeps the Core bytes the Helper was built against', () {
    final config =
        loadYaml(
              File('linux/packaging/rpm/make_config.yaml').readAsStringSync(),
            )
            as YamlMap;
    final macros = (config['spec_macros'] as YamlList).cast<String>();

    expect(macros, contains('%global debug_package %{nil}'));
    expect(macros, contains('%global __os_install_post %{nil}'));
  });
}
