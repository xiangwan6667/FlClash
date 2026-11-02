import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;
import 'package:setup_hooks/src/build.dart';
import 'package:setup_hooks/src/build_cache.dart';
import 'package:setup_hooks/src/core_builder.dart';
import 'package:setup_hooks/src/error.dart';
import 'package:setup_hooks/src/fingerprint.dart';
import 'package:setup_hooks/src/target.dart';
import 'package:setup_hooks/src/util.dart';
import 'package:test/test.dart';

void main() {
  late Directory repository;
  late Directory packageRoot;
  late Directory outputShared;

  setUp(() {
    repository = Directory.systemTemp.createTempSync('setup_core_builder_');
    repository = Directory(repository.resolveSymbolicLinksSync());
    File(
      p.join(repository.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: x\n');
    Directory(p.join(repository.path, 'core')).createSync();
    packageRoot = Directory(p.join(repository.path, 'plugins', 'setup'))
      ..createSync(recursive: true);
    outputShared = Directory(p.join(repository.path, 'out'))..createSync();
  });

  tearDown(() {
    repository.deleteSync(recursive: true);
  });

  BuildInput buildInput({
    required OS os,
    required Architecture architecture,
    bool codeAssets = true,
    bool linkingEnabled = false,
    Uri? compiler,
    Directory? package,
    Map<String, Object?> userDefines = const {},
  }) {
    final builder = BuildInputBuilder()
      ..setupShared(
        packageRoot: (package ?? packageRoot).uri,
        packageName: 'setup',
        outputDirectoryShared: outputShared.uri,
        outputFile: repository.uri.resolve('output.json'),
        userDefines: PackageUserDefines(
          workspacePubspec: PackageUserDefinesSource(
            defines: userDefines,
            basePath: repository.uri,
          ),
        ),
      )
      ..setupBuildInput()
      ..config.setupBuild(linkingEnabled: linkingEnabled);
    if (codeAssets) {
      CodeAssetExtension(
        targetArchitecture: architecture,
        targetOS: os,
        linkModePreference: LinkModePreference.dynamic,
        cCompiler: compiler == null
            ? null
            : CCompilerConfig(
                compiler: compiler,
                archiver: compiler.resolve('llvm-ar'),
                linker: compiler.resolve('ld.lld'),
              ),
        android: os == OS.android ? AndroidCodeConfig(targetNdkApi: 23) : null,
      ).setupBuildInput(builder);
    }
    return builder.build();
  }

  group('requestFor', () {
    test('has nothing to build without code assets or on iOS', () {
      const builder = CoreBuilder();

      expect(
        builder.requestFor(
          buildInput(
            os: OS.linux,
            architecture: Architecture.x64,
            codeAssets: false,
          ),
        ),
        isNull,
      );
      expect(
        builder.requestFor(
          buildInput(os: OS.iOS, architecture: Architecture.arm64),
        ),
        isNull,
      );
    });

    test('resolves the repository and target from the hook input', () {
      final request = const CoreBuilder().requestFor(
        buildInput(os: OS.linux, architecture: Architecture.x64),
      )!;

      expect(request.rootDir, repository.path);
      expect(request.harnessDir, p.join(packageRoot.path, 'setup_hooks'));
      expect(request.target, Target.linuxAmd64);
    });

    test('skips the macOS slice the host does not run', () {
      const builder = CoreBuilder(hostArchitecture: Architecture.arm64);

      expect(
        builder.requestFor(
          buildInput(os: OS.macOS, architecture: Architecture.x64),
        ),
        isNull,
      );
      expect(
        builder
            .requestFor(
              buildInput(os: OS.macOS, architecture: Architecture.arm64),
            )!
            .target,
        Target.macosArm64,
      );
    });

    test('leaves Android to the :core Gradle module', () {
      final bin = p.join(repository.path, 'ndk', 'prebuilt', 'host', 'bin');

      expect(
        const CoreBuilder().requestFor(
          buildInput(
            os: OS.android,
            architecture: Architecture.arm64,
            compiler: Uri.file(p.join(bin, 'clang')),
          ),
        ),
        isNull,
      );
    });

    test('rejects an architecture without a Core', () {
      expect(
        () => const CoreBuilder().requestFor(
          buildInput(os: OS.windows, architecture: Architecture.ia32),
        ),
        throwsA(isA<BuildException>()),
      );
    });

    test('fails when the package is not inside the repository', () {
      final elsewhere = Directory(
        p.join(repository.path, 'elsewhere', 'plugins', 'setup'),
      )..createSync(recursive: true);

      expect(
        () => const CoreBuilder().requestFor(
          buildInput(
            os: OS.linux,
            architecture: Architecture.x64,
            package: elsewhere,
          ),
        ),
        throwsA(isA<InfraError>()),
      );
    });
  });

  group('run', () {
    test(
      'reports read files, written files and directories as dependencies',
      () async {
        final goFile = p.join(repository.path, 'core', 'lib.go');
        final coreDir = p.join(repository.path, 'libclash', 'linux');
        BuildRequest? seen;
        final builder = CoreBuilder(
          build: (request) async {
            seen = request;
            return BuildReport(
              inputs: [goFile],
              outputs: [
                p.join(coreDir, 'FlClashCore'),
                p.join(coreDir, 'FlClashHelperService'),
                p.join(coreDir, 'manifest.json'),
              ],
              rebuilt: true,
            );
          },
        );
        final output = BuildOutputBuilder();

        await builder.run(
          input: buildInput(os: OS.linux, architecture: Architecture.x64),
          output: output,
        );

        expect(seen?.target, Target.linuxAmd64);
        expect(BuildOutput(output.json).dependencies, [
          Uri.file(goFile),
          Uri.file(p.join(coreDir, 'FlClashCore')),
          Uri.file(p.join(coreDir, 'FlClashHelperService')),
          Uri.file(p.join(coreDir, 'manifest.json')),
          Uri.directory(coreDir),
        ]);
      },
    );

    test(
      'restores shared artifacts after another hook mode overwrites them',
      () async {
        final source = File(p.join(repository.path, 'core', 'lib.go'));
        final coreDir = Directory(
          p.join(repository.path, 'libclash', 'windows'),
        )..createSync(recursive: true);
        final core = File(p.join(coreDir.path, 'FlClashCore.exe'));
        final helper = File(p.join(coreDir.path, 'FlClashHelperService.exe'));
        final manifest = File(p.join(coreDir.path, coreManifestName));
        final cache = BuildCache(rootDir: repository.path);
        final snapshots = <bool, ({List<Uri> dependencies, String digest})>{};
        var builds = 0;
        var hookRuns = 0;
        final builder = CoreBuilder(
          build: (_) async {
            hookRuns++;
            final execution = await cache.run(
              key: 'windows-amd64-core',
              fingerprint: () async => Fingerprint(source.readAsStringSync()),
              primaryOutput: core.path,
              notice: BuildNotice(),
              build: () async {
                builds++;
                core.writeAsStringSync('core-${source.readAsStringSync()}');
                final coreSha256 = await calcSha256(core.path);
                helper.writeAsStringSync('helper-$coreSha256');
                writeCoreManifest(path: manifest.path, coreSha256: coreSha256);
                return [core.path, helper.path, manifest.path];
              },
            );
            return BuildReport(
              inputs: [source.path],
              outputs: execution.outputs,
              rebuilt: execution.rebuilt,
            );
          },
        );

        String dependencyDigest(List<Uri> dependencies) {
          final values = <String>[];
          for (final dependency in dependencies) {
            final path = p.fromUri(dependency);
            switch (FileSystemEntity.typeSync(path)) {
              case FileSystemEntityType.file:
                values.add(
                  sha256.convert(File(path).readAsBytesSync()).toString(),
                );
              case FileSystemEntityType.directory:
                final names =
                    Directory(path)
                        .listSync()
                        .map((entry) => p.basename(entry.path))
                        .toList()
                      ..sort();
                values.add(names.join('\n'));
              default:
                values.add('missing:$path');
            }
          }
          return values.join('\n');
        }

        Future<void> runHook({required bool linkingEnabled}) async {
          final snapshot = snapshots[linkingEnabled];
          if (snapshot != null &&
              dependencyDigest(snapshot.dependencies) == snapshot.digest) {
            return;
          }
          final output = BuildOutputBuilder();
          await builder.run(
            input: buildInput(
              os: OS.windows,
              architecture: Architecture.x64,
              linkingEnabled: linkingEnabled,
            ),
            output: output,
          );
          final dependencies = BuildOutput(output.json).dependencies;
          snapshots[linkingEnabled] = (
            dependencies: dependencies,
            digest: dependencyDigest(dependencies),
          );
        }

        source.writeAsStringSync('dev');
        await runHook(linkingEnabled: true);
        final devSha256 = await calcSha256(core.path);
        source.writeAsStringSync('main');
        await runHook(linkingEnabled: false);
        expect(await calcSha256(core.path), isNot(devSha256));

        source.writeAsStringSync('dev');
        await runHook(linkingEnabled: true);
        expect(await calcSha256(core.path), devSha256);
        expect(helper.readAsStringSync(), 'helper-$devSha256');
        expect(jsonDecode(manifest.readAsStringSync()), {
          'coreSha256': devSha256,
        });
        expect(builds, 3);

        await runHook(linkingEnabled: true);
        expect(builds, 3);
        expect(hookRuns, 3);
        helper.deleteSync();
        await runHook(linkingEnabled: true);
        expect(helper.existsSync(), isTrue);
        expect(await calcSha256(core.path), devSha256);
        expect(builds, 4);
        expect(hookRuns, 4);
      },
    );

    test('declares no dependencies when nothing is built', () async {
      var built = false;
      final builder = CoreBuilder(
        build: (_) async {
          built = true;
          throw StateError('unreachable');
        },
      );
      final output = BuildOutputBuilder();

      await builder.run(
        input: buildInput(os: OS.iOS, architecture: Architecture.arm64),
        output: output,
      );

      expect(built, isFalse);
      expect(BuildOutput(output.json).dependencies, isEmpty);
    });

    test('skips the build when the user-define asks for it', () async {
      var built = false;
      final builder = CoreBuilder(
        build: (_) async {
          built = true;
          throw StateError('unreachable');
        },
      );
      final output = BuildOutputBuilder();

      await builder.run(
        input: buildInput(
          os: OS.linux,
          architecture: Architecture.x64,
          userDefines: {'build_assets': false},
        ),
        output: output,
      );

      expect(built, isFalse);
      expect(BuildOutput(output.json).dependencies, isEmpty);
      final log = File(
        p.join(repository.path, '.dart_tool', 'setup_build_cache', 'hook.log'),
      ).readAsStringSync();
      expect(log, contains('skipped: user-define build_assets=false'));
    });

    test('builds when the user-define holds any other value', () {
      const builder = CoreBuilder();

      expect(
        builder.requestFor(
          buildInput(
            os: OS.linux,
            architecture: Architecture.x64,
            userDefines: {'build_assets': true},
          ),
        ),
        isNotNull,
      );
    });

    test('reports a failed compile as a build failure', () {
      final builder = CoreBuilder(
        build: (_) async => throw CommandFailedException(
          executable: 'go',
          arguments: const ['build'],
          exitCode: 2,
          stdout: '',
          stderr: 'undefined: x',
        ),
      );

      expect(
        builder.run(
          input: buildInput(os: OS.linux, architecture: Architecture.x64),
          output: BuildOutputBuilder(),
        ),
        throwsA(
          isA<BuildError>().having(
            (error) => error.message,
            'message',
            contains('undefined: x'),
          ),
        ),
      );
    });

    test('reports a vanished build input as an infrastructure failure', () {
      final builder = CoreBuilder(
        build: (_) async =>
            throw const FileSystemException('Cannot open file', 'core/lib.go'),
      );

      expect(
        builder.run(
          input: buildInput(os: OS.linux, architecture: Architecture.x64),
          output: BuildOutputBuilder(),
        ),
        throwsA(
          isA<InfraError>().having(
            (error) => error.message,
            'message',
            contains('core/lib.go'),
          ),
        ),
      );
    });

    test('reports a missing toolchain as an infrastructure failure', () {
      final builder = CoreBuilder(
        build: (_) async =>
            throw const ProcessException('go', ['version'], 'not found'),
      );

      expect(
        builder.run(
          input: buildInput(os: OS.linux, architecture: Architecture.x64),
          output: BuildOutputBuilder(),
        ),
        throwsA(
          isA<InfraError>().having(
            (error) => error.message,
            'message',
            contains('go'),
          ),
        ),
      );
    });
  });
}
