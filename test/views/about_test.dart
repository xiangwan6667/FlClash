import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/about.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:prism_ui/prism_ui.dart' show ListHeader;

import '../helpers/test_app.dart';

enum _CheckResult { noRelease, sameVersion, offline }

class _CheckAdapter implements HttpClientAdapter {
  _CheckAdapter(this.result);

  final _CheckResult result;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (result == _CheckResult.offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    if (result == _CheckResult.sameVersion) {
      return ResponseBody.fromString(
        '[{"tag_name":"v1.2.3-rs.1","prerelease":true}]',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    if (options.uri.host == 'api.github.com') {
      return ResponseBody.fromString(
        '[]',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      '',
      302,
      headers: {
        HttpHeaders.locationHeader: [
          'https://github.com/xiangwan6667/FlClash/releases',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> pumpAbout(WidgetTester tester, Size size) async {
  PackageInfo? previous;
  try {
    previous = globalState.packageInfo;
  } catch (_) {
    previous = null;
  }
  globalState.packageInfo = PackageInfo(
    appName: 'FlClash',
    packageName: 'app.flclash.fork.rs',
    version: '1.2.3-rs.1',
    buildNumber: '1',
  );
  addTearDown(() {
    if (previous case final info?) globalState.packageInfo = info;
  });

  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const TestApp(locale: Locale('zh', 'CN'), child: AboutView()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final size in [const Size(390, 800), const Size(1200, 900)]) {
    testWidgets('the about page opens each repository at $size', (
      tester,
    ) async {
      await pumpAbout(tester, size);
      expect(find.text('GPL-3.0'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ListHeader && widget.title == '项目',
        ),
        findsNothing,
      );

      for (final (labelText, url) in [
        ('github.com/$repository', 'https://github.com/$repository'),
        ('github.com/$coreRepository', 'https://github.com/$coreRepository'),
        (
          'github.com/$upstreamRepository',
          'https://github.com/$upstreamRepository',
        ),
        (
          'github.com/$upstreamCoreRepository',
          'https://github.com/$upstreamCoreRepository',
        ),
        ('t.me/FlClash', 'https://t.me/FlClash'),
      ]) {
        final label = find.text(labelText);
        await tester.scrollUntilVisible(
          label,
          200,
          scrollable: find.descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          ),
        );
        expect(label, findsOneWidget);
        await tester.tap(label);
        await tester.pumpAndSettle();
        expect(find.text(url), findsOneWidget);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }

      await tester.scrollUntilVisible(
        find.text('Arue'),
        200,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('June2'), findsOneWidget);
      expect(find.text('Arue'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final (result, message) in [
    (_CheckResult.noRelease, '当前应用已经是最新版了'),
    (_CheckResult.sameVersion, '当前应用已经是最新版了'),
    (_CheckResult.offline, '无法连接到服务器，请检查网络连接或代理设置'),
  ]) {
    testWidgets('manual update check reports $result', (tester) async {
      final originalAdapter = request.dio.httpClientAdapter;
      request.dio.httpClientAdapter = _CheckAdapter(result);
      addTearDown(() => request.dio.httpClientAdapter = originalAdapter);
      await pumpAbout(tester, const Size(390, 800));

      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();

      expect(find.text(message), findsOneWidget);
      if (result == _CheckResult.offline) {
        expect(
          find.text(currentAppLocalizations.checkUpdateError),
          findsNothing,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('the download test reports when no release exists', (
    tester,
  ) async {
    final originalAdapter = request.dio.httpClientAdapter;
    final originalAsset = resolveSelfUpdateAsset;
    request.dio.httpClientAdapter = _CheckAdapter(_CheckResult.noRelease);
    resolveSelfUpdateAsset = () =>
        selfUpdateAssetFor(Abi.androidArm64, windowsInstalled: false);
    addTearDown(() {
      request.dio.httpClientAdapter = originalAdapter;
      resolveSelfUpdateAsset = originalAsset;
    });
    await pumpAbout(tester, const Size(390, 800));

    final pending = globalState.container
        .read(commonActionProvider.notifier)
        .testUpdateDownload();
    await tester.pumpAndSettle();
    await pending;

    expect(find.text('当前应用已经是最新版了'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
