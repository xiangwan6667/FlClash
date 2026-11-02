import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('REALITY verification fields survive editing and JSON reload', () {
    final verify = List.filled(2603, 'A').join();
    const proxy = CustomProxy(
      id: 1,
      definition: {'name': 'Test', 'type': 'vless'},
    );
    final edited = proxy
        .withField(ProxyField.realityPublicKey, 'public-test-key')
        .withField(ProxyField.realityShortId, '00010203')
        .withField(ProxyField.realityMLDSA65Verify, verify)
        .withField(ProxyField.realityClientVersion, '26.10.31')
        .withField(ProxyField.realityHybrid, false);
    final restored = CustomProxy.fromJson(edited.toJson());
    expect(restored.valueOf(ProxyField.realityMLDSA65Verify), verify);
    expect(restored.valueOf(ProxyField.realityShortId), '00010203');
    expect(restored.valueOf(ProxyField.realityHybrid), false);
    expect(restored.valueOf(ProxyField.realityClientVersion), '26.10.31');
    expect(TextInputLimits.realityMLDSA65Verify, verify.length);
    expect(
      restored.choicesOf(ProxyField.flow),
      contains('xtls-rprx-vision-udp443'),
    );
  });

  test('Snell v6 offers its own options while legacy versions keep obfs', () {
    const proxy = CustomProxy(
      id: 1,
      definition: {'name': 'Test', 'type': 'snell'},
    );
    final legacy = proxy.withField(ProxyField.version, 4);
    expect(legacy.options, contains(ProxyField.obfsMode));
    expect(legacy.options, isNot(contains(ProxyField.snellV6Mode)));
    final v6 = legacy
        .withField(ProxyField.version, 6)
        .withField(ProxyField.snellV6Mode, 'unshaped')
        .withField(ProxyField.snellClientId, 'public-test-client');
    expect(v6.options, contains(ProxyField.snellV6Mode));
    expect(v6.options, contains(ProxyField.snellClientId));
    expect(v6.options, isNot(contains(ProxyField.obfsMode)));
    expect(v6.choicesOf(ProxyField.snellV6Mode), [
      'default',
      'unshaped',
      'unsafe-raw',
    ]);
    final restored = CustomProxy.fromJson(v6.toJson());
    expect(restored.valueOf(ProxyField.version), 6);
    expect(restored.definition['v6-mode'], 'unshaped');
    expect(restored.definition['client-id'], 'public-test-client');
  });
}
