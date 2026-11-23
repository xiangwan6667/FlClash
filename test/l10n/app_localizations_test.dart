import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('load resolves accessors for every supported locale', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      final appLocalizations = loadAppLocalizations(locale);

      expect(currentAppLocalizations.localeName, appLocalizations.localeName);
      expect(appLocalizations.dashboard, isNotEmpty);
      expect(appLocalizations.proxies, isNotEmpty);
      expect(appLocalizations.settings, isNotEmpty);
      expect(appLocalizations.secondsCount(30), contains('30'));
      expect(appLocalizations.geoUpdated('geoip'), contains('geoip'));
    }
  });

  test('delegate recognizes only supported locales', () {
    expect(AppLocalizations.delegate.isSupported(const Locale('en')), isTrue);
    expect(AppLocalizations.delegate.isSupported(const Locale('de')), isFalse);
    expect(
      AppLocalizations.delegate.shouldReload(AppLocalizations.delegate),
      isFalse,
    );
  });

  test(
    'update completion messages retain upstream wording in every locale',
    () {
      const messages = {
        'en': 'The app is already up to date',
        'zh': '当前应用已经是最新版了',
        'ja': 'すでに最新バージョンです',
        'ru': 'У вас уже последняя версия',
        'fr': 'L’app est déjà à jour',
        'es': 'La app ya está actualizada',
        'ko': '이미 최신 버전입니다',
      };

      for (final locale in AppLocalizations.supportedLocales) {
        expect(
          lookupAppLocalizations(locale).checkUpdateError,
          messages[locale.languageCode],
          reason: locale.toString(),
        );
      }
    },
  );
}
