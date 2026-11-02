import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/about.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    container.listen(appSettingProvider, (_, _) {});
    globalState.container = container;
    globalState.packageInfo = PackageInfo(
      appName: appName,
      packageName: 'com.follow.clash.miu',
      version: '0.9.3',
      buildNumber: '1',
    );
  });

  tearDown(() => container.dispose());

  Future<void> pumpAbout(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container.read(viewSizeProvider.notifier).value = const Size(390, 844);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const TestApp(child: AboutView()),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  testWidgets('shows only the ordinary update button without a channel popup', (
    tester,
  ) async {
    await pumpAbout(tester);
    expect(
      find.text('v${globalState.packageInfo.displayVersion}'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(TonalButton, currentAppLocalizations.checkUpdate),
      findsOneWidget,
    );
    expect(find.byType(TonalButton), findsOneWidget);
    expect(find.byType(PopupAnchor), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disables the update button while a check is active', (
    tester,
  ) async {
    container.read(loadingProvider(LoadingTag.checkUpdate).notifier).value =
        true;
    await pumpAbout(tester, settle: false);
    final button = tester.widget<TonalButton>(
      find.widgetWithText(TonalButton, currentAppLocalizations.checkUpdate),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'update button uses regular page text without changing disabled color',
    (tester) async {
      await pumpAbout(tester);
      final text = tester.widget<RichText>(
        find.descendant(
          of: find.widgetWithText(
            TonalButton,
            currentAppLocalizations.checkUpdate,
          ),
          matching: find.byType(RichText),
        ),
      );
      final style = text.text.style!;
      expect(style.fontWeight, AppTextStyle.subheadline.weight);
      expect(style.fontSize, AppTextStyle.subheadline.size);
      container.read(loadingProvider(LoadingTag.checkUpdate).notifier).value =
          true;
      await tester.pump();
      await tester.pump(commonDuration);
      final disabledText = tester.widget<RichText>(
        find.descendant(
          of: find.widgetWithText(
            TonalButton,
            currentAppLocalizations.checkUpdate,
          ),
          matching: find.byType(RichText),
        ),
      );
      expect(disabledText.text.style!.color!.a, closeTo(0.38, 0.01));
    },
  );
}
