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

  testWidgets('selects and remembers a channel when the sheet reopens', (
    tester,
  ) async {
    await pumpAbout(tester);
    expect(find.text(channelLabel()), findsOneWidget);
    await tester.tap(find.text(channelLabel()));
    await tester.pumpAndSettle();
    const selected = defaultUpdateChannel == UpdateChannel.stable
        ? UpdateChannel.preview
        : UpdateChannel.stable;
    expect(find.byType(SelectionCheck), findsOneWidget);
    await tester.tap(find.text(selected.label));
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).updateChannel, selected);
    expect(find.text(channelLabel()), findsOneWidget);
    await tester.tap(find.text(channelLabel()));
    await tester.pumpAndSettle();
    final row = tester.widget<DecorationListItem>(
      find.widgetWithText(DecorationListItem, selected.label),
    );
    expect(row.isSelected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling leaves the saved channel unchanged', (tester) async {
    await pumpAbout(tester);
    await tester.tap(find.text(channelLabel()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(currentAppLocalizations.cancel));
    await tester.pumpAndSettle();
    expect(
      container.read(appSettingProvider).updateChannel,
      defaultUpdateChannel,
    );
    expect(find.text(currentAppLocalizations.updateChannel), findsNothing);
  });

  testWidgets('uses the floating card sheet and expands with top space', (
    tester,
  ) async {
    await pumpAbout(tester);
    await tester.tap(find.text(channelLabel()));
    await tester.pumpAndSettle();
    final handle = find.byType(SheetDragHandle);
    expect(handle, findsOneWidget);
    final restingTop = tester.getTopLeft(handle).dy;
    expect(restingTop, greaterThan(250));
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    final expandedTop = tester.getTopLeft(handle).dy;
    expect(expandedTop, lessThan(restingTop - 100));
    expect(expandedTop, greaterThan(40));
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
