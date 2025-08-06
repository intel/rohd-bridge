// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_merge_test.dart
// Unit tests for merging of ports.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class MyPortInterface extends PairInterface {
  MyPortInterface() : super(portsFromProvider: [Logic.port('myIntfPort')]);

  @override
  MyPortInterface clone() => MyPortInterface();
}

void main() {
  group('ports', () {
    test('simple port merge', () async {
      final leaf1 = BridgeModule('leaf1')..addInput('myPort', null);
      final leaf2 = BridgeModule('leaf2')..addInput('myPort', null);

      final mid = BridgeModule('mid')
        ..addSubModule(leaf1)
        ..addSubModule(leaf2);

      final topMod = BridgeModule('top')
        ..addSubModule(mid)
        ..addInput('myPort', null);

      connectPorts(topMod.port('myPort'), leaf1.port('myPort'));
      connectPorts(topMod.port('myPort'), leaf2.port('myPort'));

      await topMod.build();

      expect(mid.inputs.length, 1);

      topMod.input('myPort').put(1);
      expect(leaf1.input('myPort').value.toInt(), 1);
      expect(leaf1.input('myPort').value.toInt(), 1);
    });

    test('interleaved port merge', () async {
      final lowerLeaf = BridgeModule('lowerLeaf')..addInput('myPort', null);

      final lowerMid = BridgeModule('lowerMid')..addSubModule(lowerLeaf);

      final upperLeaf = BridgeModule('upperLeaf')..addInput('myPort', null);

      final upperMid = BridgeModule('upperMid')
        ..addSubModule(upperLeaf)
        ..addSubModule(lowerMid);

      final topMod = BridgeModule('top')
        ..addSubModule(upperMid)
        ..addInput('myPort', null);

      connectPorts(topMod.port('myPort'), upperLeaf.port('myPort'));
      connectPorts(
        // agnostic to name of the upperMid port
        upperMid.port(upperMid.inputs.keys.first),

        lowerLeaf.port('myPort'),
      );

      await topMod.build();

      // should only have one myPort punched down at the upperMid level
      expect(upperMid.inputs.length, 1);

      topMod.input('myPort').put(1);
      expect(lowerLeaf.input('myPort').value.toInt(), 1);
      expect(upperLeaf.input('myPort').value.toInt(), 1);
    });

    test('chained port merge', () async {
      final leaf1 = BridgeModule('leaf1')..addInput('myPort', null);
      final leaf2 = BridgeModule('leaf2')..addInput('myPort', null);

      final lowerMid = BridgeModule('lowerMid')
        ..addSubModule(leaf1)
        ..addSubModule(leaf2);

      final upperMid = BridgeModule('upperMid')
        ..addSubModule(lowerMid)
        ..addInput('myPort', null);

      final topMod = BridgeModule('top')
        ..addSubModule(upperMid)
        ..addInput('myPort', null);

      connectPorts(topMod.port('myPort'), upperMid.port('myPort'));
      connectPorts(upperMid.port('myPort'), leaf1.port('myPort'));
      connectPorts(topMod.port('myPort'), leaf2.port('myPort'));

      await topMod.build();

      expect(lowerMid.inputs.length, 1);

      topMod.input('myPort').put(1);
      expect(leaf1.input('myPort').value.toInt(), 1);
      expect(leaf2.input('myPort').value.toInt(), 1);
    });

    test('double chained port merge', () async {
      final leaf1 = BridgeModule('leaf1')..addInput('myPort', null);
      final leaf2 = BridgeModule('leaf2')..addInput('myPort', null);

      final lowerMid = BridgeModule('lowerMid')
        ..addSubModule(leaf1)
        ..addSubModule(leaf2);

      final midMid = BridgeModule('midMid')
        ..addSubModule(lowerMid)
        ..addInput('myPort', null);

      final upperMid = BridgeModule('upperMid')
        ..addSubModule(midMid)
        ..addInput('myPort', null);

      final topMod = BridgeModule('top')
        ..addSubModule(upperMid)
        ..addInput('myPort', null);

      connectPorts(topMod.port('myPort'), upperMid.port('myPort'));
      connectPorts(upperMid.port('myPort'), midMid.port('myPort'));
      connectPorts(midMid.port('myPort'), leaf1.port('myPort'));
      connectPorts(topMod.port('myPort'), leaf2.port('myPort'));

      await topMod.build();

      expect(lowerMid.inputs.length, 1);

      topMod.input('myPort').put(1);
      expect(leaf1.input('myPort').value.toInt(), 1);
      expect(leaf2.input('myPort').value.toInt(), 1);
    });
  });

  group('interface', () {
    test('port merges with interface port through hierarchy simply', () async {
      final leafWithIntf = BridgeModule('leafWithIntf');
      final leafWithPort = BridgeModule('leafWithPort')
        ..addInput('myPort', null);

      leafWithIntf.addInterface(
        MyPortInterface(),
        name: 'myIntf',
        role: PairRole.consumer,
      );

      final mid = BridgeModule('mid')
        ..addSubModule(leafWithIntf)
        ..addSubModule(leafWithPort);

      final topMod = BridgeModule('top')
        ..addSubModule(mid)
        ..pullUpInterface(leafWithIntf.interface('myIntf'),
            newIntfName: 'myIntf');
      connectPorts(topMod.interface('myIntf').port('myIntfPort'),
          leafWithPort.port('myPort'));

      await topMod.build();

      topMod.input('myIntf_myIntfPort').put(1);

      expect(leafWithPort.input('myPort').value.toInt(), 1);
      expect(leafWithIntf.input('myIntf_myIntfPort').value.toInt(), 1);

      expect(mid.inputs.length, 1);
    });

    test('port merges with interface port through hierarchy interleave',
        () async {
      final lowerLeaf = BridgeModule('lowerLeaf')..addInput('myPort', null);

      final lowerMid = BridgeModule('lowerMid')..addSubModule(lowerLeaf);

      final upperLeaf = BridgeModule('upperLeaf')
        ..addInterface(MyPortInterface(),
            name: 'myIntf', role: PairRole.consumer);

      final upperMid = BridgeModule('upperMid')
        ..addSubModule(upperLeaf)
        ..addSubModule(lowerMid);

      final topMod = BridgeModule('top')..addSubModule(upperMid);

      upperMid.pullUpInterface(upperLeaf.interface('myIntf'),
          newIntfName: 'myIntf');
      topMod.addInput('myPort', null);
      connectPorts(topMod.port('myPort'),
          upperMid.interface('myIntf').port('myIntfPort'));
      connectPorts(
        topMod.port('myPort'),
        lowerLeaf.port('myPort'),
      );

      await topMod.build();

      // should only have one myPort punched down at the upperMid level
      expect(upperMid.inputs.length, 1);

      topMod.input('myPort').put(1);
      expect(lowerLeaf.input('myPort').value.toInt(), 1);
      expect(
          upperLeaf.interface('myIntf').port('myIntfPort').port.value.toInt(),
          1);
    });
  });
}
