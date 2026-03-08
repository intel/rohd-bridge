// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// sub_interface_test.dart
// Tests for interfaces with sub-interfaces.
//
// 2026 March 8
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class SubIntf extends PairInterface {
  SubIntf()
      : super(
          portsFromProvider: [Logic.port('subFp', 8)],
          portsFromConsumer: [Logic.port('subFc', 8)],
        );

  @override
  SubIntf clone() => SubIntf();
}

class IntfWithSub extends PairInterface {
  IntfWithSub()
      : super(
          portsFromProvider: [Logic.port('topFp', 8)],
          portsFromConsumer: [Logic.port('topFc', 8)],
        ) {
    addSubInterface('sub', SubIntf());
  }

  @override
  IntfWithSub clone() => IntfWithSub();
}

void main() {
  group('interfaces with sub-interfaces', () {
    test('connectUpTo passes signals through sub-interfaces', () async {
      final top = BridgeModule('top')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.consumer);

      final leaf = BridgeModule('leaf')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.consumer);

      top.addSubModule(leaf);

      leaf.interface('intf').connectUpTo(top.interface('intf'));

      top.pullUpPort(leaf.createPort('dummy', PortDirection.inOut));

      await top.build();

      // top-level interface ports
      top.interface('intf').port('topFp').port.put(0xAB);
      expect(leaf.interface('intf').port('topFp').port.value.toInt(), 0xAB);

      leaf.interface('intf').port('topFc').port.put(0xCD);
      expect(top.interface('intf').port('topFc').port.value.toInt(), 0xCD);

      // sub-interface ports (accessed via module ports)
      top.input('intf_subFp').put(0x12);
      expect(leaf.input('intf_subFp').value.toInt(), 0x12);

      leaf.output('intf_subFc').put(0x34);
      expect(top.output('intf_subFc').value.toInt(), 0x34);
    });

    test('connectDownTo passes signals through sub-interfaces', () async {
      final top = BridgeModule('top')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.provider);

      final leaf = BridgeModule('leaf')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.provider);

      top.addSubModule(leaf);

      top.interface('intf').connectDownTo(leaf.interface('intf'));

      top.pullUpPort(leaf.createPort('dummy', PortDirection.inOut));

      await top.build();

      // top-level interface ports
      top.interface('intf').port('topFp').port.put(0xAB);
      expect(leaf.interface('intf').port('topFp').port.value.toInt(), 0xAB);

      leaf.interface('intf').port('topFc').port.put(0xCD);
      expect(top.interface('intf').port('topFc').port.value.toInt(), 0xCD);

      // sub-interface ports (accessed via module ports)
      top.input('intf_subFc').put(0x12);
      expect(leaf.input('intf_subFc').value.toInt(), 0x12);

      leaf.output('intf_subFp').put(0x34);
      expect(top.output('intf_subFp').value.toInt(), 0x34);
    });

    test('connectTo passes signals through sub-interfaces', () async {
      final top = BridgeModule('top');

      final provider = BridgeModule('provider')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.provider);

      final consumer = BridgeModule('consumer')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.consumer);

      top
        ..addSubModule(provider)
        ..addSubModule(consumer);

      provider.interface('intf').connectTo(consumer.interface('intf'));

      top
        ..pullUpPort(provider.createPort('dummy', PortDirection.inOut))
        ..pullUpPort(consumer.createPort('dummy', PortDirection.inOut));

      await top.build();

      // top-level interface ports
      provider.interface('intf').port('topFp').port.put(0xAB);
      expect(consumer.interface('intf').port('topFp').port.value.toInt(), 0xAB);

      consumer.interface('intf').port('topFc').port.put(0xCD);
      expect(provider.interface('intf').port('topFc').port.value.toInt(), 0xCD);

      // sub-interface ports (accessed via module ports)
      provider.output('intf_subFp').put(0x12);
      expect(consumer.input('intf_subFp').value.toInt(), 0x12);

      consumer.output('intf_subFc').put(0x34);
      expect(provider.input('intf_subFc').value.toInt(), 0x34);
    });

    test('connectUpTo throws when exceptPorts used with sub-interfaces', () {
      final top = BridgeModule('top')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.consumer);

      final leaf = BridgeModule('leaf')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.consumer);

      top.addSubModule(leaf);

      expect(
        () => leaf
            .interface('intf')
            .connectUpTo(top.interface('intf'), exceptPorts: {'topFp'}),
        throwsA(isA<RohdBridgeException>()),
      );
    });

    test('connectDownTo throws when exceptPorts used with sub-interfaces', () {
      final top = BridgeModule('top')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.provider);

      final leaf = BridgeModule('leaf')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.provider);

      top.addSubModule(leaf);

      expect(
        () => top
            .interface('intf')
            .connectDownTo(leaf.interface('intf'), exceptPorts: {'topFp'}),
        throwsA(isA<RohdBridgeException>()),
      );
    });

    test('connectTo throws when exceptPorts used with sub-interfaces', () {
      final top = BridgeModule('top');

      final provider = BridgeModule('provider')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.provider);

      final consumer = BridgeModule('consumer')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.consumer);

      top
        ..addSubModule(provider)
        ..addSubModule(consumer);

      expect(
        () => provider
            .interface('intf')
            .connectTo(consumer.interface('intf'), exceptPorts: {'topFp'}),
        throwsA(isA<RohdBridgeException>()),
      );
    });

    test('punchUpTo throws when exceptPorts used with sub-interfaces', () {
      final top = BridgeModule('top');

      final leaf = BridgeModule('leaf')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.consumer);

      top.addSubModule(leaf);

      expect(
        () => leaf.interface('intf').punchUpTo(top, exceptPorts: {'topFp'}),
        throwsA(isA<RohdBridgeException>()),
      );
    });

    test('punchDownTo throws when exceptPorts used with sub-interfaces', () {
      final top = BridgeModule('top')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.provider);

      final leaf = BridgeModule('leaf');
      top.addSubModule(leaf);

      expect(
        () => top.interface('intf').punchDownTo(leaf, exceptPorts: {'topFp'}),
        throwsA(isA<RohdBridgeException>()),
      );
    });

    test('punchUpTo passes signals through sub-interfaces', () async {
      final top = BridgeModule('top');

      final leaf = BridgeModule('leaf')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.consumer);

      top.addSubModule(leaf);

      leaf.interface('intf').punchUpTo(top);

      await top.build();

      top.input('intf_subFp').put(0x12);
      expect(leaf.input('intf_subFp').value.toInt(), 0x12);

      leaf.output('intf_subFc').put(0x34);
      expect(top.output('intf_subFc').value.toInt(), 0x34);
    });

    test('punchDownTo passes signals through sub-interfaces', () async {
      final top = BridgeModule('top')
        ..addInterface(IntfWithSub(), name: 'intf', role: PairRole.provider);

      final leaf = BridgeModule('leaf');
      top.addSubModule(leaf);

      top.interface('intf').punchDownTo(leaf);

      await top.build();

      top.input('intf_subFc').put(0x12);
      expect(leaf.input('intf_subFc').value.toInt(), 0x12);

      leaf.output('intf_subFp').put(0x34);
      expect(top.output('intf_subFp').value.toInt(), 0x34);
    });
  });
}
