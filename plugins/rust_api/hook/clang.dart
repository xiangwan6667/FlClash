import 'dart:io';

String? clangBuiltinInclude(String resourceDir) {
  if (resourceDir.isEmpty) return null;
  final directory = Directory('$resourceDir${Platform.pathSeparator}include');
  final stdbool = File('${directory.path}${Platform.pathSeparator}stdbool.h');
  return stdbool.existsSync() ? directory.path : null;
}

String? findLibclang(Directory llvmRoot, {String? windowsFallback}) {
  for (final name in const ['lib', 'lib64']) {
    final directory = Directory(
      '${llvmRoot.path}${Platform.pathSeparator}$name',
    );
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return directory.path;
    }
  }
  if (windowsFallback != null && windowsFallback.isNotEmpty) {
    final file = File(windowsFallback);
    if (file.existsSync() && _isLibclang(file)) return file.path;
    final directory = Directory(windowsFallback);
    if (directory.existsSync() && directory.listSync().any(_isLibclang)) {
      return directory.path;
    }
  }
  return null;
}

bool _isLibclang(FileSystemEntity entity) {
  return entity.uri.pathSegments.last.toLowerCase().startsWith('libclang.');
}
