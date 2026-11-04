import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get displayVersion {
    const release = String.fromEnvironment('APP_RELEASE_VERSION');
    return release.isEmpty ? version : release;
  }

  String get ua => [
    '$appName/v$displayVersion',
    'clash-verge',
    'Platform/${Platform.operatingSystem}',
  ].join(' ');
}

int compareVersions(String version1, String version2) {
  Version parse(String value) => Version.parse(
    value.replaceFirstMapped(
      RegExp(r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?'),
      (match) => '${match[1]}.${match[2] ?? '0'}.${match[3] ?? '0'}',
    ),
  );
  return parse(version1).compareTo(parse(version2));
}

const releaseNotesBeginMarker = '<!-- flclash:changelog:begin -->';
const releaseNotesEndMarker = '<!-- flclash:changelog:end -->';

List<String> parseReleaseBody(String? body) {
  if (body == null) return [];
  final regex = RegExp(r'^[ \t]*-[ \t]+(.*)$', multiLine: true);
  return regex
      .allMatches(scopeReleaseNotes(body))
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

String scopeReleaseNotes(String body) {
  final begin = body.indexOf(releaseNotesBeginMarker);
  if (begin < 0) return body;
  final start = begin + releaseNotesBeginMarker.length;
  final end = body.indexOf(releaseNotesEndMarker, start);
  return end < 0 ? body.substring(start) : body.substring(start, end);
}
