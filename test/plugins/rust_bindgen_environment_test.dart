import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../plugins/rust_api/hook/clang.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('flclash-clang-test');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('uses the host LLVM when a Windows NDK has no libclang', () {
    final host = Directory('${root.path}${Platform.pathSeparator}host')
      ..createSync();
    File(
      '${host.path}${Platform.pathSeparator}libclang.dll',
    ).writeAsStringSync('');

    expect(findLibclang(root, windowsFallback: host.path), host.path);
    final library = '${host.path}${Platform.pathSeparator}libclang.dll';
    expect(findLibclang(root, windowsFallback: library), library);
  });

  test('uses the NDK library when it is available', () {
    final lib = Directory('${root.path}${Platform.pathSeparator}lib')
      ..createSync();
    File(
      '${lib.path}${Platform.pathSeparator}libclang.so',
    ).writeAsStringSync('');

    expect(findLibclang(root), lib.path);
  });

  test('does not accept an unavailable host LLVM', () {
    expect(findLibclang(root, windowsFallback: '${root.path}/missing'), isNull);
  });

  test('finds the built-in headers in the NDK clang resource directory', () {
    final include = Directory('${root.path}${Platform.pathSeparator}include')
      ..createSync();
    File(
      '${include.path}${Platform.pathSeparator}stdbool.h',
    ).writeAsStringSync('');

    expect(clangBuiltinInclude(root.path), include.path);
    expect(clangBuiltinInclude('${root.path}/missing'), isNull);
  });
}
