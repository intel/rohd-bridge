// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// uniquification_test.dart
// Unit tests for uniquifying ports and interfaces as they are created.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class MyIntf extends PairInterface {
  MyIntf()
      : super(
          portsFromProvider: [Logic.port('portFromProvider')],
          portsFromConsumer: [Logic.port('portFromConsumer')],
        );

  @override
  MyIntf clone() => MyIntf();
}

enum LeftRightBlockUnique { none, left, right }

void main() {
  group('port uniquification', () {
    test('simple pull-up', () async {
      final leaf1 = BridgeModule('leaf')..addOutput('a');
      final leaf2 = BridgeModule('leaf')..addOutput('a');
      final mid = BridgeModule('mid')
        ..addSubModule(leaf1)
        ..addSubModule(leaf2);
      final top = BridgeModule('top')
        ..addSubModule(mid)
        ..pullUpPort(leaf1.port('a'))
        ..pullUpPort(leaf2.port('a'));

      await top.build();

      expect(mid.outputs.length, 2);
      expect(top.outputs.length, 2);
    });

    test('uniq disabled at module causes error', () {
      final leaf1 = BridgeModule('leaf')..addOutput('a');
      final leaf2 = BridgeModule('leaf')..addOutput('a');
      final mid = BridgeModule('mid', allowUniquification: false)
        ..addSubModule(leaf1)
        ..addSubModule(leaf2)
        ..addInput('leaf_a_0', null); // name already exists at mid
      final top = BridgeModule('top')
        ..addSubModule(mid)
        ..pullUpPort(leaf1.port('a'));

      expect(() => top.pullUpPort(leaf2.port('a')), throwsException);
    });

    test('uniq disabled at pull-up causes error', () {
      final leaf1 = BridgeModule('leaf')..addOutput('a');
      final leaf2 = BridgeModule('leaf')..addOutput('a');
      final mid = BridgeModule('mid', allowUniquification: false)
        ..addSubModule(leaf1)
        ..addSubModule(leaf2);
      final top = BridgeModule('top')
        ..addSubModule(mid)
        ..pullUpPort(leaf1.port('a'));

      expect(
          () => top.pullUpPort(leaf2.port('a'), allowPortUniquification: false),
          throwsException);
    });

    test('simple up and down, two routes same names', () async {
      final leftLeaf1 = BridgeModule('leafTx')..addOutput('a');
      final leftLeaf2 = BridgeModule('leafTx')..addOutput('a');
      final rightLeaf1 = BridgeModule('leafRx')..addInput('a', null);
      final rightLeaf2 = BridgeModule('leafRx')..addInput('a', null);
      final midLeft = BridgeModule('midLeft')
        ..addSubModule(leftLeaf1)
        ..addSubModule(leftLeaf2);
      final midRight = BridgeModule('midRight')
        ..addSubModule(rightLeaf1)
        ..addSubModule(rightLeaf2);
      final top = BridgeModule('top')
        ..addSubModule(midLeft)
        ..addSubModule(midRight);
      connectPorts(leftLeaf1.port('a'), rightLeaf1.port('a'));
      connectPorts(leftLeaf2.port('a'), rightLeaf2.port('a'));

      // just to connect it to top-level
      midLeft.addInput('clk', null);
      top.pullUpPort(midLeft.port('clk'));

      await top.build();

      expect(midLeft.outputs.length, 2);
      expect(midRight.inputs.length, 2);

      // port names should be uniquified, based on leaf name also, and connected
      // properly
      midLeft.port('leafTx_a').port.put(1);
      midLeft.port('leafTx_a_0').port.put(0);
      expect(midRight.port('leafRx_a').port.value.toInt(), 1);
      expect(midRight.port('leafRx_a_0').port.value.toInt(), 0);
    });

    group('simple up and down, two routes same names with rename', () {
      for (final uniqueBlockType in LeftRightBlockUnique.values) {
        test('unique block ${uniqueBlockType.name}', () async {
          final leftLeaf1 = BridgeModule('leafTx')..addOutput('a');
          final leftLeaf2 = BridgeModule('leafTx')..addOutput('a');
          final rightLeaf1 = BridgeModule('leafRx')..addInput('a', null);
          final rightLeaf2 = BridgeModule('leafRx')..addInput('a', null);
          final midLeft = BridgeModule('midLeft')
            ..addSubModule(leftLeaf1)
            ..addSubModule(leftLeaf2);
          final midRight = BridgeModule('midRight')
            ..addSubModule(rightLeaf1)
            ..addSubModule(rightLeaf2);
          final top = BridgeModule('top')
            ..addSubModule(midLeft)
            ..addSubModule(midRight);
          connectPorts(leftLeaf1.port('a'), rightLeaf1.port('a'),
              driverPathNewPortName: 'my_a',
              receiverPathNewPortName: 'their_a');

          if (uniqueBlockType == LeftRightBlockUnique.none) {
            connectPorts(leftLeaf2.port('a'), rightLeaf2.port('a'),
                driverPathNewPortName: 'my_a',
                receiverPathNewPortName: 'their_a');
          } else {
            expect(
                () => connectPorts(leftLeaf2.port('a'), rightLeaf2.port('a'),
                    driverPathNewPortName: 'my_a',
                    receiverPathNewPortName: 'their_a',
                    allowDriverPathUniquification:
                        uniqueBlockType != LeftRightBlockUnique.left,
                    allowReceiverPathUniquification:
                        uniqueBlockType != LeftRightBlockUnique.right),
                throwsException);
            return;
          }

          // just to connect it to top-level
          midLeft.addInput('clk', null);
          top.pullUpPort(midLeft.port('clk'));

          await top.build();

          expect(midLeft.outputs.length, 2);
          expect(midRight.inputs.length, 2);

          // port names should be uniquified, based on leaf name also, and
          // connected properly
          midLeft.port('my_a').port.put(1);
          midLeft.port('my_a_0').port.put(0);
          expect(midRight.port('their_a').port.value.toInt(), 1);
          expect(midRight.port('their_a_0').port.value.toInt(), 0);
        });
      }
    });
  });

  group('interface uniquification', () {
    test('simple pull-up', () async {
      final leaf1 = BridgeModule('leaf')
        ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.provider);
      final leaf2 = BridgeModule('leaf')
        ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.provider);

      final mid = BridgeModule('mid')
        ..addSubModule(leaf1)
        ..addSubModule(leaf2);
      final top = BridgeModule('top')
        ..addSubModule(mid)
        ..pullUpInterface(leaf1.interface('myIntf'))
        ..pullUpInterface(leaf2.interface('myIntf'));

      await top.build();

      expect(mid.outputs.length, 2);
      expect(top.outputs.length, 2);
      expect(mid.inputs.length, 2);
      expect(top.inputs.length, 2);
    });

    test('pull up interface uniquify middle correctly', () async {
      final leaf = BridgeModule('leaf')
        ..addInterface(MyIntf(), name: 'intfA', role: PairRole.provider);

      final mid = BridgeModule('mid')
        ..addInterface(MyIntf(), name: 'intfA', role: PairRole.provider)
        ..addSubModule(leaf);

      final top = BridgeModule('top')
        ..addSubModule(mid)
        ..pullUpInterface(leaf.interface('intfA'));

      await top.build();

      expect(top.tryOutput('intfA_portFromProvider'), isNotNull);
    });

    test('uniq disabled at module causes error', () {
      final leaf1 = BridgeModule('leaf')
        ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.provider);
      final leaf2 = BridgeModule('leaf')
        ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.provider);

      final mid = BridgeModule('mid', allowUniquification: false)
        ..addSubModule(leaf1)
        ..addSubModule(leaf2)
        ..addInterface(MyIntf(),
            name: 'myIntf_0',
            role: PairRole.provider); // name already exists at mid

      final top = BridgeModule('top')
        ..addSubModule(mid)
        ..pullUpInterface(leaf1.interface('myIntf'));

      expect(() => top.pullUpInterface(leaf2.interface('myIntf')),
          throwsException);
    });

    test('uniq disabled at pull-up causes error', () {
      final leaf1 = BridgeModule('leaf')
        ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.provider);
      final leaf2 = BridgeModule('leaf')
        ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.provider);

      final mid = BridgeModule('mid', allowUniquification: false)
        ..addSubModule(leaf1)
        ..addSubModule(leaf2);

      final top = BridgeModule('top')
        ..addSubModule(mid)
        ..pullUpInterface(leaf1.interface('myIntf'));

      expect(
          () => top.pullUpInterface(leaf2.interface('myIntf'),
              allowIntfUniquification: false),
          throwsException);
    });

    group('simple up and down with rename', () {
      for (final uniqueBlockType in LeftRightBlockUnique.values) {
        test('unique block ${uniqueBlockType.name}', () async {
          final leftLeaf1 = BridgeModule('leafTx')
            ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.provider);
          final leftLeaf2 = BridgeModule('leafTx')
            ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.provider);
          final rightLeaf1 = BridgeModule('leafRx')
            ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.consumer);
          final rightLeaf2 = BridgeModule('leafRx')
            ..addInterface(MyIntf(), name: 'myIntf', role: PairRole.consumer);
          final midLeft = BridgeModule('midLeft')
            ..addSubModule(leftLeaf1)
            ..addSubModule(leftLeaf2);
          final midRight = BridgeModule('midRight')
            ..addSubModule(rightLeaf1)
            ..addSubModule(rightLeaf2);
          final top = BridgeModule('top')
            ..addSubModule(midLeft)
            ..addSubModule(midRight);
          connectInterfaces(
              leftLeaf1.interface('myIntf'), rightLeaf1.interface('myIntf'),
              intf1PathNewName: 'leftIntf', intf2PathNewName: 'rightIntf');

          if (uniqueBlockType == LeftRightBlockUnique.none) {
            connectInterfaces(
                leftLeaf2.interface('myIntf'), rightLeaf2.interface('myIntf'),
                intf1PathNewName: 'leftIntf', intf2PathNewName: 'rightIntf');
          } else {
            expect(
                () => connectInterfaces(leftLeaf2.interface('myIntf'),
                    rightLeaf2.interface('myIntf'),
                    intf1PathNewName: 'leftIntf',
                    intf2PathNewName: 'rightIntf',
                    allowIntf1PathUniquification:
                        uniqueBlockType != LeftRightBlockUnique.left,
                    allowIntf2PathUniquification:
                        uniqueBlockType != LeftRightBlockUnique.right),
                throwsException);
            return;
          }

          // just to connect it to top-level
          midLeft.addInput('clk', null);
          top.pullUpPort(midLeft.port('clk'));

          await top.build();

          expect(midLeft.inputs.length, 2 + 1);
          expect(midLeft.outputs.length, 2);
          expect(midRight.inputs.length, 2);
          expect(midRight.outputs.length, 2);

          // port names should be uniquified, based on leaf name also, and
          // connected properly
          midLeft.interface('leftIntf').port('portFromProvider').port.put(1);
          midRight
              .interface('rightIntf_0')
              .port('portFromConsumer')
              .port
              .put(0);

          expect(
              midRight
                  .interface('rightIntf')
                  .port('portFromProvider')
                  .port
                  .value
                  .toInt(),
              1);
          expect(
              midLeft
                  .interface('leftIntf_0')
                  .port('portFromConsumer')
                  .port
                  .value
                  .toInt(),
              0);
        });
      }
    });
  });
}
