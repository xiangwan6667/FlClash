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

  String channelLabel() => currentAppLocalizations.updateChannelValue(
    container.read(appSettingProvider).updateChannel.label,
  );

  testWidgets('selects and remembers a channel when the menu reopens', (
    tester,
  ) async {
    await pumpAbout(tester);
    expect(find.text(channelLabel()), findsOneWidget);
    await tester.tap(find.text(channelLabel()));
    await tester.pumpAndSettle();
    const selected = defaultUpdateChannel == UpdateChannel.stable
        ? UpdateChannel.preview
        : UpdateChannel.stable;
    expect(find.byType(CommonPopupMenu), findsOneWidget);
    await tester.tap(find.text(selected.label));
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).updateChannel, selected);
    expect(find.text(channelLabel()), findsOneWidget);
    await tester.tap(find.text(channelLabel()));
    await tester.pumpAndSettle();
    final menu = tester.widget<CommonPopupMenu>(find.byType(CommonPopupMenu));
    expect(
      menu.items.singleWhere((item) => item.checked == true).label,
      selected.label,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing the menu leaves the saved channel unchanged', (
    tester,
  ) async {
    await pumpAbout(tester);
    await tester.tap(find.text(channelLabel()));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(
      container.read(appSettingProvider).updateChannel,
      defaultUpdateChannel,
    );
    expect(find.byType(CommonPopupMenu), findsNothing);
  });

  testWidgets('leaving About while the menu closes does not use its ref', (
    tester,
  ) async {
    await pumpAbout(tester);
    await tester.tap(find.text(channelLabel()));
    await tester.pumpAndSettle();
    const selected = defaultUpdateChannel == UpdateChannel.stable
        ? UpdateChannel.preview
        : UpdateChannel.stable;
    await tester.tap(find.text(selected.label));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a compact popup beside the channel button', (tester) async {
    await pumpAbout(tester);
    await tester.tap(find.text(channelLabel()));
    await tester.pumpAndSettle();
    expect(find.byType(SheetDragHandle), findsNothing);
    expect(find.byType(CommonPopupMenu), findsOneWidget);
    expect(tester.getSize(find.byType(PopupMenuCard)).height, lessThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not allow switching while an update check is active', (
    tester,
  ) async {
    container.read(loadingProvider(LoadingTag.checkUpdate).notifier).value =
        true;
    await pumpAbout(tester, settle: false);
    final button = tester.widget<TonalButton>(
      find.widgetWithText(TonalButton, channelLabel()),
    );
    expect(button.onPressed, isNull);
  });
}
