import 'dart:convert';
import 'dart:io';

import 'git.dart';
import 'models.dart';
import 'parser.dart';
import 'render.dart';

/// Versions up to and including this tag are frozen: they predate the
/// structured pipeline and are kept verbatim at the bottom of `CHANGELOG.md`.
const frozenBoundaryTag = 'v0.8.96';

const changelogDataPath = 'changelog.json';

const changelogMarkdownPath = 'CHANGELOG.md';

class PendingVersion {
  const PendingVersion({
    required this.version,
    required this.date,
    this.prerelease = false,
  });

  final String version;
  final String date;
  final bool prerelease;

  String get tag => 'v$version';
}

class ChangelogBuildResult {
  const ChangelogBuildResult({
    required this.changelog,
    required this.warnings,
    this.commitIdsByTag = const <String, Set<String>>{},
    this.squashedIdsByTag = const <String, Set<String>>{},
  });

  final Changelog changelog;
  final List<String> warnings;

  /// Short hashes of every commit that fed each version, including the ones
  /// that produced no entry. `verify` uses it to allow hand written entries as
  /// long as they point at a commit that really is in the version's range.
  final Map<String, Set<String>> commitIdsByTag;
  final Map<String, Set<String>> squashedIdsByTag;
}

class ChangelogBuilder {
  ChangelogBuilder(this.git, {this.boundary = frozenBoundaryTag});

  final Git git;
  final String boundary;

  ChangelogBuildResult build({PendingVersion? pending}) {
    final boundaryTag = VersionTag.tryParse(boundary);
    final stable = git
        .stableTags()
        .where((tag) => boundaryTag == null || tag.compareTo(boundaryTag) > 0)
        .toList();
    final parser = ChangelogParser();
    final versions = <ChangelogVersion>[];
    final commitIdsByTag = <String, Set<String>>{};
    final squashedIdsByTag = <String, Set<String>>{};

    if (pending != null && !git.tagExists(pending.tag)) {
      final commits = git.commits(
        from: stable.isEmpty ? boundaryTag?.name : stable.first.name,
        to: 'HEAD',
      );
      final squashed = _squashedIdsOf(commits);
      squashedIdsByTag[pending.tag] = squashed;
      commitIdsByTag[pending.tag] = {..._idsOf(commits), ...squashed};
      versions.add(
        ChangelogVersion(
          version: pending.version,
          tag: pending.tag,
          date: pending.date,
          prerelease: pending.prerelease,
          groups: groupItems(parser.parseAll(commits)),
        ),
      );
    }

    for (var index = 0; index < stable.length; index++) {
      final tag = stable[index];
      final previous = index + 1 < stable.length
          ? stable[index + 1].name
          : boundaryTag?.name;
      final commits = git.commits(from: previous, to: tag.name);
      final squashed = _squashedIdsOf(commits);
      squashedIdsByTag[tag.name] = squashed;
      commitIdsByTag[tag.name] = {..._idsOf(commits), ...squashed};
      versions.add(
        ChangelogVersion(
          version: tag.version,
          tag: tag.name,
          date: git.tagDate(tag.name),
          groups: groupItems(parser.parseAll(commits)),
        ),
      );
    }

    return ChangelogBuildResult(
      changelog: Changelog(versions: versions),
      warnings: parser.warnings,
      commitIdsByTag: commitIdsByTag,
      squashedIdsByTag: squashedIdsByTag,
    );
  }

  Set<String> _idsOf(List<RawCommit> commits) =>
      commits.map((commit) => commit.shortHash).toSet();

  Set<String> _squashedIdsOf(List<RawCommit> commits) {
    final trailer = RegExp(
      r'^Squashed-Commit: ([0-9a-f]{40})$',
      multiLine: true,
    );
    return {
      for (final commit in commits)
        for (final match in trailer.allMatches(commit.body))
          match.group(1)!.substring(0, 7),
    };
  }
}

/// Keep published notes whose original commits are recorded in a squash.
Changelog preserveSquashedNotes(
  ChangelogBuildResult built,
  Changelog recorded,
) {
  final versions = {
    for (final version in built.changelog.versions) version.tag: version,
  };
  for (final version in recorded.versions) {
    final tag = VersionTag.tryParse(version.tag);
    final ids = {
      for (final group in version.groups)
        for (final entry in group.entries) entry.id,
    };
    if (tag == null || ids.isEmpty) continue;
    final current = versions[version.tag];
    if (current != null && !current.isEmpty) continue;
    for (final source in built.squashedIdsByTag.entries) {
      final owner = VersionTag.tryParse(source.key);
      if (owner != null &&
          tag.compareTo(owner) <= 0 &&
          source.value.containsAll(ids)) {
        versions[version.tag] = version;
        break;
      }
    }
  }
  final ordered = versions.values.toList()
    ..sort(
      (a, b) =>
          VersionTag.tryParse(b.tag)!.compareTo(VersionTag.tryParse(a.tag)!),
    );
  return Changelog(versions: ordered);
}

final _frozenComment = RegExp(r'\s*<!--.*?-->', dotAll: true);

/// End of the generated head: the frozen marker plus whatever comment lines
/// follow it. Matching comments by shape rather than by text means the note can
/// be reworded without stranding the previous wording in the frozen tail.
int _frozenBoundary(String content) {
  final markerIndex = content.indexOf(changelogFrozenMarker);
  if (markerIndex < 0) {
    return -1;
  }
  var cursor = markerIndex + changelogFrozenMarker.length;
  while (true) {
    final match = _frozenComment.matchAsPrefix(content, cursor);
    if (match == null) {
      return cursor;
    }
    cursor = match.end;
  }
}

String mergeMarkdown(String rendered, String existing) {
  final boundary = _frozenBoundary(existing);
  if (boundary < 0) {
    var tail = existing.trimLeft();
    if (tail.startsWith(changelogTitle)) {
      tail = tail.substring(changelogTitle.length).trimLeft();
    }
    return '$rendered$tail';
  }
  return '$rendered${existing.substring(boundary).trimLeft()}';
}

String markdownHead(String content) {
  final boundary = _frozenBoundary(content);
  return boundary < 0 ? content : content.substring(0, boundary);
}

/// Tags [derived] has a version for that [recorded] never wrote down.
///
/// This is what catches a release tagged without running `release` first. The
/// entry-by-entry checks in `verify` only look at versions both sides have, so
/// a version missing from `changelog.json` outright would otherwise pass and
/// only surface at the end of the release, when `render` finds no notes for the
/// tag being published.
List<String> missingReleaseTags(Changelog recorded, Changelog derived) {
  final known = <String>{for (final version in recorded.versions) version.tag};
  return <String>[
    for (final version in derived.versions)
      if (!known.contains(version.tag)) version.tag,
  ];
}

String encodeChangelog(Changelog changelog) =>
    '${const JsonEncoder.withIndent('  ').convert(changelog.toJson())}\n';

Changelog decodeChangelog(String source) =>
    Changelog.fromJson(jsonDecode(source) as Map<String, dynamic>);

String readPubspecVersion(String pubspec) {
  final match = RegExp(
    r'^version:\s*(\d+\.\d+\.\d+)',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw StateError('No version found in pubspec.yaml');
  }
  return match.group(1)!;
}

String today() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
}

File resolve(String root, String path) {
  final separator = Platform.pathSeparator;
  if (path.startsWith(separator) || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
    return File(path);
  }
  return File('$root$separator$path');
}
