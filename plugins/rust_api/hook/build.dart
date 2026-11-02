import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:flutter_rust_bridge_hooks/flutter_rust_bridge_hooks.dart';

import 'clang.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (input.userDefines['build_assets'] == false) {
      stdout.writeln('Skipping the Rust build: user-define build_assets=false');
      return;
    }
    await FlutterRustBridgeNativeAssetsBuilder(
      cratePath: 'rust',
      extraCargoEnvironmentVariables: _bindgenEnvironment(input),
    ).run(input: input, output: output);
  });
}

// Windows NDKs do not ship libclang, so bindgen needs a host LLVM installation.
Map<String, String> _bindgenEnvironment(BuildInput input) {
  if (!input.config.buildCodeAssets ||
      input.config.code.targetOS != OS.android) {
    return const {};
  }
  final compiler = input.config.code.cCompiler?.compiler;
  if (compiler == null) {
    return const {};
  }
  final llvmRoot = File.fromUri(compiler).parent.parent;
  final libclang = findLibclang(
    llvmRoot,
    windowsFallback: Platform.isWindows
        ? Platform.environment['LIBCLANG_PATH']
        : null,
  );
  if (libclang == null) {
    throw StateError(
      'No libclang under ${llvmRoot.path} (lib or lib64). On Windows, install '
      'LLVM and set LIBCLANG_PATH to its libclang.dll or containing directory.',
    );
  }
  final environment = {'LIBCLANG_PATH': libclang};
  if (Platform.isWindows) {
    final result = Process.runSync(File.fromUri(compiler).path, [
      '-print-resource-dir',
    ]);
    final include = result.exitCode == 0
        ? clangBuiltinInclude((result.stdout as String).trim())
        : null;
    if (include == null) {
      throw StateError(
        'The Android NDK clang built-in headers were not found.',
      );
    }
    environment['C_INCLUDE_PATH'] = [
      include,
      if (Platform.environment['C_INCLUDE_PATH'] case final String existing
          when existing.isNotEmpty)
        existing,
    ].join(';');
  }
  return environment;
}
