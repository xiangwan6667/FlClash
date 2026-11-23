import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/release_asset.dart';
import 'package:fl_clash/models/clash_config.dart' show defaultTunDevice;
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import '../../tool/package.dart' as package;
import '../../tool/src/package/context.dart';
import '../../tool/src/package/windows.dart';

PackageContext _context(ReleaseOs os, ReleaseArch arch) {
  return PackageContext(
    root: Directory.current.path,
    os: os,
    arch: arch,
    line: ReleaseLine.rs,
    version: '0.9.4-rs.1.4',
    channel: 'pre',
    commit: 'c' * 40,
    pubspecVersion: '0.9.4+4',
    description: 'A proxy client.',
    outputDirectory: 'dist',
  );
}

void main() {
  test('uses an independent Fork identity across desktop and Android', () {
    final android = File('android/app/build.gradle.kts').readAsStringSync();
    final linux = File('linux/CMakeLists.txt').readAsStringSync();
    final macos = File(
      'macos/Runner/Configs/AppInfo.xcconfig',
    ).readAsStringSync();
    final windows = _context(
      ReleaseOs.windows,
      ReleaseArch.amd64,
    ).makeConfig('exe');

    expect(android, contains('applicationId = "app.flclash.fork.rs"'));
    expect(linux, contains('set(APPLICATION_ID "app.flclash.fork.rs")'));
    expect(macos, contains('PRODUCT_BUNDLE_IDENTIFIER = app.flclash.fork.rs'));
    expect(windows['display_name'], packageDisplayName);
    expect(windows['install_dir_name'], r'{autopf64}\FlClash-rs');
    expect(windows['app_id'], 'A97DB4C4-D63D-441E-B40A-28A40AB90133');
    expect(defaultTunDevice.length, lessThanOrEqualTo(15));
  });

  test('the current packager renders an empty Windows publisher', () {
    final context = _context(ReleaseOs.windows, ReleaseArch.amd64);
    final config = context.makeConfig('exe');
    final template = File(
      'windows/packaging/exe/${config['script_template']}',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final script = renderInnoScript(
      template,
      innoVariables(context, config, sourceDir: 'stage', outputBaseName: 'out'),
    );

    expect(config['publisher'], isEmpty);
    expect(script, contains('AppPublisher=\n'));
    expect(script, contains('AppPublisherURL=https://github.com/$repository'));
    expect(script, contains('CloseApplications=force\n'));
    expect(
      script,
      contains('Where-Object { \$_.Path -and \$_.Path.StartsWith('),
    );
    expect(script, contains('[StringComparison]::OrdinalIgnoreCase) }'));
    expect(script, isNot(contains('taskkill')));
  });

  for (final arch in [ReleaseArch.amd64, ReleaseArch.arm64]) {
    test('isolates ${arch.name} Windows shortcuts from upstream', () {
      final context = _context(ReleaseOs.windows, arch);
      final config = context.makeConfig('exe');
      final template = File(
        'windows/packaging/exe/${config['script_template']}',
      ).readAsStringSync();
      final script = renderInnoScript(
        template,
        innoVariables(
          context,
          config,
          sourceDir: 'stage',
          outputBaseName: 'out',
        ),
      );

      expect(
        script,
        contains(
          r'Name: "{autoprograms}\\FlClash-rs\\FlClash RS"; Filename: "{app}\\FlClash-RS.exe"',
        ),
      );
      expect(
        script,
        contains(
          r'Name: "{autodesktop}\\FlClash-rs\\FlClash RS"; Filename: "{app}\\FlClash-RS.exe"',
        ),
      );
      expect(script, isNot(contains(r'Name: "{autoprograms}\\FlClash RS";')));
      expect(script, isNot(contains(r'Name: "{autodesktop}\\FlClash RS";')));
    });
  }

  test('the release template links every package the current entry plans', () {
    final template = File('.github/release_template.md')
        .readAsStringSync()
        .replaceAll('TAG', 'v0.9.4-rs.1+4')
        .replaceAll('LINE', 'rs')
        .replaceAll('VERSION', '0.9.4-rs.1.4');
    final names = <String>{};
    for (final os in ReleaseOs.values) {
      final arches = os == ReleaseOs.android
          ? const [ReleaseArch.universal]
          : const [ReleaseArch.amd64, ReleaseArch.arm64];
      for (final arch in arches) {
        for (final target in package.defaultTargets[os]!) {
          final plan = package.planTarget(
            _context(os, arch),
            target,
            androidArches: const [
              ReleaseArch.arm64,
              ReleaseArch.armv7,
              ReleaseArch.amd64,
            ],
          );
          names.addAll(plan.artifacts.map((artifact) => artifact.name));
        }
      }
    }

    expect(names, hasLength(15));
    for (final name in names) {
      expect(
        template,
        contains(
          'https://github.com/$repository/releases/download/v0.9.4-rs.1+4/$name',
        ),
        reason: name,
      );
    }
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
        expect(scripts, contains('rm -f $helperUnitPath'));
        if (format == 'deb') {
          final maintainer = config['maintainer'] as YamlMap;
          expect(maintainer['name'], 'FlClash Fork');
          expect(maintainer['email'], 'noreply@localhost');
        } else {
          expect(config['packager'], 'FlClash Fork');
          expect(config['packagerEmail'], 'noreply@localhost');
        }
        expect(
          scripts.any((script) => script.contains('systemctl daemon-reload')),
          isTrue,
        );
      });
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
