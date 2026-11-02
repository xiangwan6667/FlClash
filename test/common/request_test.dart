import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StalledHttpClient extends Fake implements HttpClient {
  @override
  Duration? connectionTimeout;

  @override
  String Function(Uri url)? findProxy;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;
}

class _HostAdapter implements HttpClientAdapter {
  _HostAdapter(this.byHost);

  final Map<String, ResponseBody Function()> byHost;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return byHost[options.uri.host]!();
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getTextResponseForUrl propagates the typed DioException', () async {
    // flutter_test's mocked HttpClient answers every request with HTTP 400,
    // which Dio surfaces as a badResponse DioException.
    await expectLater(
      request.getTextResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  test('getFileResponseForUrl propagates the typed DioException', () async {
    await expectLater(
      request.getFileResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  group('latestRelease', () {
    Request requestAnswering(List<Map<String, dynamic>> releases) {
      return Request()
        ..dio.httpClientAdapter = _HostAdapter({
          'api.github.com': () => ResponseBody.fromString(
            jsonEncode(releases),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        });
    }

    test('uses the saved channel instead of the build branch', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.listen(appSettingProvider, (_, _) {});
      final stable = {'tag_name': 'v1.2.3', 'target_commitish': 'Miu'};
      final preview = {'tag_name': 'v1.2.4', 'target_commitish': 'Miu-dev'};
      final request = requestAnswering([preview, stable])
        ..attach(container.read);
      for (final (channel, expected) in [
        ('stable', stable),
        ('preview', preview),
      ]) {
        container
            .read(appSettingProvider.notifier)
            .update(
              (_) => AppSettingProps.fromJson({'updateChannel': channel}),
            );
        expect(await request.latestRelease(), expected);
      }
    });

    test(
      'discards a result when its channel changed during the request',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container.listen(appSettingProvider, (_, _) {});
        final request = requestAnswering([
          {'tag_name': 'v1.2.3', 'target_commitish': updateBranch},
        ])..attach(container.read);
        request.dio.interceptors.add(
          InterceptorsWrapper(
            onResponse: (response, handler) {
              container
                  .read(appSettingProvider.notifier)
                  .update(
                    (state) => state.copyWith(
                      updateChannel:
                          defaultUpdateChannel == UpdateChannel.stable
                          ? UpdateChannel.preview
                          : UpdateChannel.stable,
                    ),
                  );
              handler.next(response);
            },
          ),
        );
        expect(await request.latestRelease(), isNull);
      },
    );

    test('only reads published releases targeting this build branch', () async {
      final own = {'tag_name': 'v1.2.3', 'target_commitish': updateBranch};
      final request = requestAnswering([
        {'tag_name': 'v9.0.0', 'target_commitish': 'other-branch'},
        {'tag_name': 'v8.0.0', 'target_commitish': updateBranch, 'draft': true},
        own,
      ]);
      request.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.uri.path, '/repos/$repository/releases');
            handler.next(options);
          },
        ),
      );
      expect(await request.latestRelease(), own);
    });

    test(
      'does not offer another branch when this branch has no release',
      () async {
        final request = requestAnswering([
          {'tag_name': 'v9.0.0', 'target_commitish': 'other-branch'},
        ]);
        expect(await request.latestRelease(), isNull);
      },
    );

    test('API failures never fall back to the global latest release', () async {
      final request = Request()
        ..dio.httpClientAdapter = _HostAdapter({
          'api.github.com': () => ResponseBody.fromString('{}', 403),
          'github.com': () => throw StateError('cross-channel fallback'),
        });
      await expectLater(request.latestRelease(), throwsA(isA<DioException>()));
    });

    test('continues past a page belonging to another branch', () async {
      var page = 0;
      final own = {'tag_name': 'v1.2.3', 'target_commitish': updateBranch};
      final request = Request()
        ..dio.httpClientAdapter = _HostAdapter({
          'api.github.com': () => ResponseBody.fromString(
            jsonEncode(
              ++page == 1
                  ? List.filled(100, {'target_commitish': 'other-branch'})
                  : [own],
            ),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          ),
        });
      expect(await request.latestRelease(), own);
      expect(page, 2);
    });
  });

  group('downloadTarget', () {
    test('sends a URL without credentials unchanged', () {
      final target = downloadTarget('https://example.com/a.yaml?x=1');

      expect(target.uri.toString(), 'https://example.com/a.yaml?x=1');
      expect(target.headers, isEmpty);
    });

    test('moves decoded credentials into the Authorization header', () {
      for (final url in [
        'https://me@mail.com:p:w@dav.example.com/dav/a.yaml',
        'https://me%40mail.com:p%3Aw@dav.example.com/dav/a.yaml',
      ]) {
        final target = downloadTarget(url);

        expect(target.uri.toString(), 'https://dav.example.com/dav/a.yaml');
        expect(
          target.headers[HttpHeaders.authorizationHeader],
          'Basic ${base64.encode(utf8.encode('me@mail.com:p:w'))}',
        );
      }
    });
  });

  group('decompressUnlabeled', () {
    final yaml = utf8.encode('proxies: []\n');

    test('inflates a gzip or zlib body that arrived unlabeled', () {
      for (final codec in [gzip, zlib]) {
        final body = Uint8List.fromList(codec.encode(yaml));

        expect(decompressUnlabeled(body), yaml);
      }
    });

    test('leaves a plain body untouched', () {
      final body = Uint8List.fromList(yaml);

      expect(decompressUnlabeled(body), same(body));
    });

    test('keeps a body that only starts like gzip', () {
      final body = Uint8List.fromList([0x1f, 0x8b, 1, 2, 3]);

      expect(decompressUnlabeled(body), same(body));
    });
  });

  testWidgets('a stalled download fails at the shared download deadline', (
    tester,
  ) async {
    late final Future<Response<String>> pending;
    HttpOverrides.runZoned(() {
      pending = Request().getTextResponseForUrl('http://127.0.0.1/stalled');
    }, createHttpClient: (_) => _StalledHttpClient());
    var settled = false;
    final outcome = expectLater(
      pending.whenComplete(() => settled = true),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.receiveTimeout,
        ),
      ),
    );

    await tester.pump(downloadTimeoutDuration - const Duration(seconds: 1));
    expect(settled, isFalse);
    await tester.pump(const Duration(seconds: 1));
    await outcome;
  });
}
