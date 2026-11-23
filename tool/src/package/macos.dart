import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'context.dart';
import 'steps.dart';

const macosProductsPath = 'build/macos/Build/Products/Release';

/// appdmg writes the window layout into `.DS_Store` itself, so packaging
/// never drives Finder.
TargetPlan planDmg(PackageContext context) {
  final config = context.makeConfig('dmg');
  final name = context.assetName(context.arch, 'dmg');
  final stage = context.stagingPath('dmg');
  final spec = p.join(stage, 'appdmg.json');
  final output = context.outputPath(name);
  final app = context.path('$macosProductsPath/${config['title']}.app');

  return TargetPlan(
    steps: [
      Task('verify and copy $app into $stage and write $spec', () async {
        await recreateDirectory(stage);
        if (!Directory(app).existsSync()) {
          throw PackageError('$app is missing');
        }
        final identifier = await capture('/usr/libexec/PlistBuddy', [
          '-c',
          'Print :CFBundleIdentifier',
          p.join(app, 'Contents', 'Info.plist'),
        ]);
        if (identifier != 'app.flclash.fork.rs') {
          throw PackageError('unexpected macOS bundle identifier $identifier');
        }
        await Command('cp', ['-RH', app, stage]).run(verbose: false);
        File(spec).writeAsStringSync(jsonEncode(config));
        final previous = File(output);
        if (previous.existsSync()) previous.deleteSync();
      }),
      Command('appdmg', [spec, output]),
    ],
    artifacts: [PlannedArtifact(name: name, arch: context.arch)],
  );
}
