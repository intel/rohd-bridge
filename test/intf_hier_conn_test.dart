// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// intf_hier_conn_test.dart
// Unit tests for building and punching through hierarchy with interfaces.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class MyIntf extends PairInterface {
  MyIntf()
      : super(
          portsFromProvider: [Logic.port('myProviderPort', 8)],
          portsFromConsumer: [Logic.port('myConsumerPort', 8)],
        );

  @override
  MyIntf clone() => MyIntf();
}

class SimpleIntfModProviderLeaf extends BridgeModule {
  SimpleIntfModProviderLeaf() : super('simple_intf_mod_provider') {
    addFromJson(jsonDecode(
        File('test/test_collaterals/simple_intf_mod_provider.json')
            .readAsStringSync()) as Map<String, dynamic>);

    addInterface(
      MyIntf(),
      name: 'myIntf',
      role: PairRole.provider,
      connect: false,
    );

    addPortMap(
        port('sv_myProviderPort'), interface('myIntf').port('myProviderPort'));
    addPortMap(
        port('sv_myConsumerPort'), interface('myIntf').port('myConsumerPort'));
  }
}

class SimpleIntfModConsumerLeaf extends BridgeModule {
  SimpleIntfModConsumerLeaf() : super('simple_intf_mod_consumer') {
    addFromJson(jsonDecode(File('test/test_collaterals/simple_intf_mod.json')
        .readAsStringSync()) as Map<String, dynamic>);

    addInterface(
      MyIntf(),
      name: 'myIntf',
      role: PairRole.consumer,
      connect: false,
    );

    addPortMap(
        port('sv_myProviderPort'), interface('myIntf').port('myProviderPort'));
    addPortMap(
        port('sv_myConsumerPort'), interface('myIntf').port('myConsumerPort'));
  }
}

void main() {
  group('connect interfaces through hierarchy', () {
    const intfName1 = 'myIntf1';
    const intfName2 = 'myIntf2';
    const putValProvider = 0xab;
    const putValConsumer = 0xcd;

    /// If [matchDirection], expects that mod1 is above mod2.
    Future<void> testConnection(
        BridgeModule Function(BridgeModule mod1, BridgeModule mod2)
            makeConnectionsAndHier,
        {bool matchDirection = false}) async {
      final mod1 = BridgeModule('mod1')
        ..addInterface(MyIntf(),
            name: intfName1,
            role: matchDirection ? PairRole.consumer : PairRole.provider);
      final mod2 = BridgeModule('mod2')
        ..addInterface(MyIntf(), name: intfName2, role: PairRole.consumer);

      final top = makeConnectionsAndHier(mod1, mod2);

      if (mod1 != top) {
        top.pullUpPort(mod1.createPort('dummy', PortDirection.inOut));
      }
      if (mod2 != top) {
        top.pullUpPort(mod2.createPort('dummy', PortDirection.inOut));
      }

      await top.build();

      // check connection by putting a value on the wire at the source and
      // reading at destination
      mod1.interface(intfName1).port('myProviderPort').port.put(putValProvider);
      mod2.interface(intfName2).port('myConsumerPort').port.put(putValConsumer);

      expect(
          mod1.interface(intfName1).port('myConsumerPort').port.value.toInt(),
          putValConsumer);
      expect(
          mod2.interface(intfName2).port('myProviderPort').port.value.toInt(),
          putValProvider);
    }

    test('in same level', () async {
      await testConnection((leaf1, leaf2) {
        final top = BridgeModule('top')
          ..addSubModule(leaf1)
          ..addSubModule(leaf2);
        connectInterfaces(
            leaf1.interface(intfName1), leaf2.interface(intfName2));
        return top;
      });
    });

    test('through multiple levels', () async {
      await testConnection((leaf1, leaf2) {
        final mid1 = BridgeModule('mid1');
        final mid2 = BridgeModule('mid2');
        final top = BridgeModule('top')
          ..addSubModule(mid1..addSubModule(leaf1))
          ..addSubModule(mid2..addSubModule(leaf2));
        connectInterfaces(
            leaf1.interface(intfName1), leaf2.interface(intfName2));

        // ensure ports actually got punched through mid levels
        expect(mid1.inputs.length, 1);
        expect(mid1.outputs.length, 1);
        expect(mid2.inputs.length, 1);
        expect(mid2.outputs.length, 1);

        return top;
      });
    });

    test('misaligned direction direct parent leaf connection fails', () async {
      try {
        await testConnection((parent, child) {
          parent.addSubModule(child);
          connectInterfaces(
              parent.interface(intfName1), child.interface(intfName2));
          return parent;
        });
        fail('Should have thrown an exception');
      } on RohdBridgeException catch (e) {
        expect(e.message, contains('Vertical connections'));
      }
    });

    test('direct parent leaf connection', () async {
      await testConnection(matchDirection: true, (parent, child) {
        parent.addSubModule(child);
        connectInterfaces(
            parent.interface(intfName1), child.interface(intfName2));
        return parent;
      });
    });

    test('direct parent leaf connection, backwards connection', () async {
      await testConnection(matchDirection: true, (parent, child) {
        parent.addSubModule(child);
        connectInterfaces(
            child.interface(intfName2), parent.interface(intfName1));
        return parent;
      });
    });

    test('parent through mid to leaf connection', () async {
      await testConnection(matchDirection: true, (parent, child) {
        final mid = BridgeModule('mid');
        parent.addSubModule(mid..addSubModule(child));
        connectInterfaces(
            parent.interface(intfName1), child.interface(intfName2));

        expect(mid.inputs.length, 1);
        expect(mid.outputs.length, 1);

        return parent;
      });
    });

    test('feed-through fails with error unsupported', () async {
      try {
        await testConnection(matchDirection: true, (leaf1, leaf2) {
          final top = BridgeModule('top')
            ..addSubModule(leaf1)
            ..addSubModule(leaf2);
          connectInterfaces(
              leaf1.interface(intfName1), leaf2.interface(intfName2));
          return top;
        });
        fail('Should have thrown an exception');
      } on RohdBridgeException catch (e) {
        expect(e.message, contains('Unhandled direction'));
        return;
      }
    });
  });

  group('pull up port', () {
    const intfName1 = 'myIntf1';
    const intfName2 = 'myIntf2';

    Future<void> testPullUp(
      BridgeModule Function(BridgeModule leaf1, BridgeModule leaf2)
          makeConnectionsAndHier,
    ) async {
      final leaf1 = BridgeModule('leaf1')
        ..addInterface(MyIntf(), name: intfName1, role: PairRole.provider);
      final leaf2 = BridgeModule('leaf2')
        ..addInterface(MyIntf(), name: intfName2, role: PairRole.consumer);

      final top = makeConnectionsAndHier(leaf1, leaf2);

      // check connection by putting a value on the wire at the source and
      // reading at destination
      top.interface(intfName1).port('myConsumerPort').port.put(0xab);
      expect(
          leaf1.interface(intfName1).port('myConsumerPort').port.value.toInt(),
          equals(0xab));

      top.interface(intfName2).port('myProviderPort').port.put(0xbc);
      expect(
          leaf2.interface(intfName2).port('myProviderPort').port.value.toInt(),
          equals(0xbc));

      leaf1.interface(intfName1).port('myProviderPort').port.put(0xcd);
      expect(top.interface(intfName1).port('myProviderPort').port.value.toInt(),
          equals(0xcd));

      leaf2.interface(intfName2).port('myConsumerPort').port.put(0xde);
      expect(top.interface(intfName2).port('myConsumerPort').port.value.toInt(),
          equals(0xde));

      // make sure cloned interfaces are still the same type
      expect(top.interface(intfName1).interface, isA<MyIntf>());
      expect(top.interface(intfName2).interface, isA<MyIntf>());
      expect(top.interface(intfName1).internalInterface, isA<MyIntf>());
      expect(top.interface(intfName2).internalInterface, isA<MyIntf>());

      await top.build();
    }

    test('in same level', () async {
      await testPullUp((leaf1, leaf2) => BridgeModule('top')
        ..addSubModule(leaf1)
        ..addSubModule(leaf2)
        ..pullUpInterface(leaf1.interface(intfName1), newIntfName: intfName1)
        ..pullUpInterface(leaf2.interface(intfName2), newIntfName: intfName2));
    });

    test('through multiple levels', () async {
      await testPullUp((leaf1, leaf2) {
        final mid1 = BridgeModule('mid1');
        final mid2 = BridgeModule('mid2');
        final top = BridgeModule('top')
          ..addSubModule(mid1..addSubModule(leaf1))
          ..addSubModule(mid2..addSubModule(leaf2))
          ..pullUpInterface(leaf1.interface(intfName1), newIntfName: intfName1)
          ..pullUpInterface(leaf2.interface(intfName2), newIntfName: intfName2);

        // ensure ports actually got punched through mid levels
        expect(mid1.inputs.length, 1);
        expect(mid1.outputs.length, 1);
        expect(mid2.inputs.length, 1);
        expect(mid2.outputs.length, 1);

        return top;
      });
    });
  });

  group('with processed SV leaves', () {
    test("connect leaves' interfaces", () async {
      final consumer = SimpleIntfModConsumerLeaf()
        ..createPort('clk', PortDirection.input);
      final provider = SimpleIntfModProviderLeaf();
      final top = BridgeModule('top')
        ..addSubModule(consumer)
        ..addSubModule(provider);
      connectInterfaces(
          consumer.interface('myIntf'), provider.interface('myIntf'));

      // so that modules are discoverable
      top.pullUpPort(consumer.port('clk'));

      await top.build();

      final sv = top.generateSynth();

      expect(
          sv,
          contains('simple_intf_mod_consumer  '
              'simple_intf_mod_consumer('
              '.sv_myProviderPort(sv_myProviderPort),'
              '.clk(simple_intf_mod_consumer_clk),'
              '.sv_myConsumerPort(sv_myConsumerPort));'));
      expect(
          sv,
          contains('simple_intf_mod_provider  '
              'simple_intf_mod_provider('
              '.sv_myConsumerPort(sv_myConsumerPort),'
              '.sv_myProviderPort(sv_myProviderPort));'));
    });
  });

  //TODO: what if instead of port map, we make a connection between interface and port!?
  // should that just be an error? probably? or maybe it should be external?
  // -if a port and interface port are on the same module, in the same direction, it should have been a port map?
  // -if they are different directions, then based on the directionality of the connection, we can deduce internal or external

  test('connect interface ports on the same module', () async {
    final leaf = BridgeModule('leaf');
    final intf1 =
        leaf.addInterface(MyIntf(), name: 'intf1', role: PairRole.provider);
    final intf2 =
        leaf.addInterface(MyIntf(), name: 'intf2', role: PairRole.consumer);

    final top = BridgeModule('top')
      ..addSubModule(leaf)
      ..pullUpPort(leaf.createPort('dummy', PortDirection.input));

    connectInterfaces(intf1, intf2);

    await top.build();

    intf1.port('myProviderPort').port.put(0x12);
    expect(intf2.port('myProviderPort').port.value.toInt(), 0x12);

    intf2.port('myConsumerPort').port.put(0x34);
    expect(intf1.port('myConsumerPort').port.value.toInt(), 0x34);

    final sv = top.generateSynth();

    // ensure no logic at all is inside the leaf
    expect(sv, contains('''
);

endmodule : leaf'''));
  });
}
