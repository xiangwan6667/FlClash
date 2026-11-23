import 'dart:io';

import 'package:path/path.dart' as p;

String sourcePath(String path) => p.split(p.relative(path)).join('/');

const sourceRoots = ['lib'];

List<FileSystemEntity> sourceEntities() => [
  for (final root in sourceRoots) ...Directory(root).listSync(recursive: true),
];
