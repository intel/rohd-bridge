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

    test('nested fan-out reuses explicitly named path ports', () async {
      final source = BridgeModule('source')..addOutput('x');
      final destination1 = BridgeModule('destination1')..addInput('a', null);
      final destination2 = BridgeModule('destination2')..addInput('b', null);

      final sourceParent = BridgeModule('sourceParent')..addSubModule(source);
      final destinationParent = BridgeModule('destinationParent')
        ..addSubModule(destination1)
        ..addSubModule(destination2);

      final top = BridgeModule('top')
        ..addSubModule(sourceParent)
        ..addSubModule(destinationParent);

      sourceParent.addInput('clk', null);
      top.pullUpPort(sourceParent.port('clk'), newPortName: 'clk');

      connectPorts(source.port('x'), destination1.port('a'),
          receiverPathNewPortName: 'x',
          allowDriverPathUniquification: false,
          allowReceiverPathUniquification: false);
      connectPorts(source.port('x'), destination2.port('b'),
          receiverPathNewPortName: 'x',
          allowDriverPathUniquification: false,
          allowReceiverPathUniquification: false);

      expect(sourceParent.outputs.keys, ['source_x']);
      expect(destinationParent.inputs.keys, ['x']);

      await top.build();

      source.output('x').put(1);
      expect(destination1.input('a').value.toInt(), 1);
      expect(destination2.input('b').value.toInt(), 1);
    });

    test('fan-out extends an existing direct parent route', () async {
      final source = BridgeModule('source')..addOutput('x');
      final destination1 = BridgeModule('destination1')..addInput('a', null);
      final destination2 = BridgeModule('destination2')..addInput('b', null);
      final destination3 = BridgeModule('destination3')..addInput('c', null);

      final sourceParent = BridgeModule('sourceParent')
        ..addSubModule(source)
        ..addOutput('x');
      final destinationParent = BridgeModule('destinationParent')
        ..addSubModule(destination1)
        ..addSubModule(destination2)
        ..addSubModule(destination3);

      final top = BridgeModule('top')
        ..addSubModule(sourceParent)
        ..addSubModule(destinationParent);

      sourceParent.addInput('clk', null);
      top.pullUpPort(sourceParent.port('clk'), newPortName: 'clk');

      connectPorts(source.port('x'), sourceParent.port('x'));
      connectPorts(source.port('x'), destination1.port('a'),
          driverPathNewPortName: 'x', receiverPathNewPortName: 'x');
      connectPorts(source.port('x'), destination2.port('b'),
          driverPathNewPortName: 'alternate',
          receiverPathNewPortName: 'alternate');
      connectPorts(source.port('x'), destination3.port('c'),
          driverPathNewPortName: 'x', receiverPathNewPortName: 'x');

      expect(sourceParent.outputs.keys, ['x', 'alternate']);
      expect(destinationParent.inputs.keys, ['x', 'alternate']);

      await top.build();

      source.output('x').put(1);
      expect(sourceParent.output('x').value.toInt(), 1);
      expect(sourceParent.output('alternate').value.toInt(), 1);
      expect(destination1.input('a').value.toInt(), 1);
      expect(destination2.input('b').value.toInt(), 1);
      expect(destination3.input('c').value.toInt(), 1);
    });

    test('fan-out keeps differently named driver paths distinct', () {
      final source = BridgeModule('source')..addOutput('x');
      final destination1 = BridgeModule('destination1')..addInput('a', null);
      final destination2 = BridgeModule('destination2')..addInput('b', null);

      final sourceParent = BridgeModule('sourceParent')..addSubModule(source);
      final destinationParent1 = BridgeModule('destinationParent1')
        ..addSubModule(destination1);
      final destinationParent2 = BridgeModule('destinationParent2')
        ..addSubModule(destination2);

      BridgeModule('top')
        ..addSubModule(sourceParent)
        ..addSubModule(destinationParent1)
        ..addSubModule(destinationParent2);

      connectPorts(source.port('x'), destination1.port('a'),
          driverPathNewPortName: 'first');
      connectPorts(source.port('x'), destination2.port('b'),
          driverPathNewPortName: 'second');

      expect(sourceParent.outputs.keys, ['first', 'second']);
    });

    test('fan-out keeps differently named receiver paths distinct', () {
      final destination1 = BridgeModule('destination1')..addInput('a', null);
      final destination2 = BridgeModule('destination2')..addInput('b', null);
      final destinationParent = BridgeModule('destinationParent')
        ..addSubModule(destination1)
        ..addSubModule(destination2);

      final top = BridgeModule('top')
        ..addInput('x', null)
        ..addSubModule(destinationParent);

      connectPorts(top.port('x'), destination1.port('a'),
          receiverPathNewPortName: 'first');
      connectPorts(top.port('x'), destination2.port('b'),
          receiverPathNewPortName: 'second');

      expect(destinationParent.inputs.keys, ['first', 'second']);
    });

    group('path name ordering', () {
      final driverCases =
          <({String description, List<String?> names, List<String> expected})>[
        (
          description: 'same explicit driver name',
          names: ['lane', 'lane'],
          expected: ['lane']
        ),
        (
          description: 'driver alias is reused after another alias',
          names: ['first', 'second', 'first'],
          expected: ['first', 'second']
        ),
        (
          description: 'unnamed driver then matching explicit name',
          names: [null, 'source_x'],
          expected: ['source_x']
        ),
        (
          description: 'unnamed driver then different explicit name',
          names: [null, 'routeAlias'],
          expected: ['source_x', 'routeAlias']
        ),
        (
          description: 'explicit driver then unnamed request',
          names: ['routeAlias', null],
          expected: ['routeAlias']
        ),
      ];

      for (final testCase in driverCases) {
        test(testCase.description, () {
          final source = BridgeModule('source')..addOutput('x');
          final sourceParent = BridgeModule('sourceParent')
            ..addSubModule(source);

          final top = BridgeModule('top')..addSubModule(sourceParent);
          for (var i = 0; i < testCase.names.length; i++) {
            final destination = BridgeModule('destination$i')
              ..addInput('dataIn', null);
            final destinationParent = BridgeModule('destinationParent$i')
              ..addSubModule(destination);
            top.addSubModule(destinationParent);

            connectPorts(source.port('x'), destination.port('dataIn'),
                driverPathNewPortName: testCase.names[i]);
          }

          expect(sourceParent.outputs.keys, testCase.expected);
        });
      }

      final receiverCases =
          <({String description, List<String?> names, List<String> expected})>[
        (
          description: 'same explicit receiver name',
          names: ['lane', 'lane'],
          expected: ['lane']
        ),
        (
          description: 'receiver alias is reused after another alias',
          names: ['first', 'second', 'first'],
          expected: ['first', 'second']
        ),
        (
          description: 'unnamed receiver then matching explicit name',
          names: [null, 'destination0_dataIn'],
          expected: ['destination0_dataIn']
        ),
        (
          description: 'unnamed receiver then different explicit name',
          names: [null, 'routeAlias'],
          expected: ['destination0_dataIn', 'routeAlias']
        ),
        (
          description: 'explicit receiver then unnamed request',
          names: ['routeAlias', null],
          expected: ['routeAlias']
        ),
      ];

      for (final testCase in receiverCases) {
        test(testCase.description, () {
          final destinationParent = BridgeModule('destinationParent');
          final top = BridgeModule('top')
            ..addInput('x', null)
            ..addSubModule(destinationParent);

          for (var i = 0; i < testCase.names.length; i++) {
            final destination = BridgeModule('destination$i')
              ..addInput('dataIn', null);
            destinationParent.addSubModule(destination);

            connectPorts(top.port('x'), destination.port('dataIn'),
                receiverPathNewPortName: testCase.names[i]);
          }

          expect(destinationParent.inputs.keys, testCase.expected);
        });
      }
    });

    group('driver and receiver path name cross-product', () {
      final testCases = <({
        String description,
        String secondDriverName,
        String secondReceiverName,
        List<String> expectedDriverNames,
        List<String> expectedReceiverNames,
      })>[
        (
          description: 'same driver and receiver names merge',
          secondDriverName: 'driver',
          secondReceiverName: 'receiver',
          expectedDriverNames: ['driver'],
          expectedReceiverNames: ['receiver'],
        ),
        (
          description:
              'same driver and different receiver names split receiver path',
          secondDriverName: 'driver',
          secondReceiverName: 'receiver2',
          expectedDriverNames: ['driver'],
          expectedReceiverNames: ['receiver', 'receiver2'],
        ),
        (
          description:
              'different driver and same receiver names split both paths',
          secondDriverName: 'driver2',
          secondReceiverName: 'receiver',
          expectedDriverNames: ['driver', 'driver2'],
          expectedReceiverNames: ['receiver', 'receiver_0'],
        ),
        (
          description: 'different driver and receiver names split both paths',
          secondDriverName: 'driver2',
          secondReceiverName: 'receiver2',
          expectedDriverNames: ['driver', 'driver2'],
          expectedReceiverNames: ['receiver', 'receiver2'],
        ),
      ];

      for (final testCase in testCases) {
        test(testCase.description, () {
          final source = BridgeModule('source')..addOutput('x');
          final destination1 = BridgeModule('destination1')
            ..addInput('a', null);
          final destination2 = BridgeModule('destination2')
            ..addInput('b', null);
          final sourceParent = BridgeModule('sourceParent')
            ..addSubModule(source);
          final destinationParent = BridgeModule('destinationParent')
            ..addSubModule(destination1)
            ..addSubModule(destination2);

          BridgeModule('top')
            ..addSubModule(sourceParent)
            ..addSubModule(destinationParent);

          connectPorts(source.port('x'), destination1.port('a'),
              driverPathNewPortName: 'driver',
              receiverPathNewPortName: 'receiver');
          connectPorts(source.port('x'), destination2.port('b'),
              driverPathNewPortName: testCase.secondDriverName,
              receiverPathNewPortName: testCase.secondReceiverName);

          expect(sourceParent.outputs.keys, testCase.expectedDriverNames);
          expect(destinationParent.inputs.keys, testCase.expectedReceiverNames);
        });
      }
    });

    test('distinct driver route respects disabled receiver uniquification', () {
      final source = BridgeModule('source')..addOutput('x');
      final destination1 = BridgeModule('destination1')..addInput('a', null);
      final destination2 = BridgeModule('destination2')..addInput('b', null);
      final sourceParent = BridgeModule('sourceParent')..addSubModule(source);
      final destinationParent = BridgeModule('destinationParent')
        ..addSubModule(destination1)
        ..addSubModule(destination2);

      BridgeModule('top')
        ..addSubModule(sourceParent)
        ..addSubModule(destinationParent);

      connectPorts(source.port('x'), destination1.port('a'),
          driverPathNewPortName: 'driver1',
          receiverPathNewPortName: 'receiver',
          allowReceiverPathUniquification: false);

      expect(
          () => connectPorts(source.port('x'), destination2.port('b'),
              driverPathNewPortName: 'driver2',
              receiverPathNewPortName: 'receiver',
              allowReceiverPathUniquification: false),
          throwsException);
    });

    test('partial receiver route extension is reused by later fan-out', () {
      final destination1 = BridgeModule('destination1')..addInput('a', null);
      final destination2 = BridgeModule('destination2')..addInput('b', null);
      final destination3 = BridgeModule('destination3')..addInput('c', null);
      final lowerBranch = BridgeModule('lowerBranch')
        ..addSubModule(destination2)
        ..addSubModule(destination3);
      final destinationInner = BridgeModule('destinationInner')
        ..addSubModule(destination1)
        ..addSubModule(lowerBranch);
      final destinationOuter = BridgeModule('destinationOuter')
        ..addSubModule(destinationInner);
      final top = BridgeModule('top')
        ..addInput('x', null)
        ..addSubModule(destinationOuter);

      for (final destination in [destination1, destination2, destination3]) {
        connectPorts(
            top.port('x'), destination.port(destination.inputs.keys.single),
            receiverPathNewPortName: 'lane');
      }

      expect(destinationOuter.inputs.keys, ['lane']);
      expect(destinationInner.inputs.keys, ['lane']);
      expect(lowerBranch.inputs.keys, ['lane']);
    });

    test('multi-level fan-out distinguishes exact and different slices',
        () async {
      final source = BridgeModule('source')
        ..createPort('bus', PortDirection.output, width: 8);
      final destination1 = BridgeModule('destination1')
        ..createPort('a', PortDirection.input, width: 4);
      final destination2 = BridgeModule('destination2')
        ..createPort('b', PortDirection.input, width: 4);
      final destination3 = BridgeModule('destination3')
        ..createPort('c', PortDirection.input, width: 4);

      final sourceInner = BridgeModule('sourceInner')..addSubModule(source);
      final sourceOuter = BridgeModule('sourceOuter')
        ..addSubModule(sourceInner);
      final destinationInner = BridgeModule('destinationInner')
        ..addSubModule(destination1)
        ..addSubModule(destination2)
        ..addSubModule(destination3);
      final destinationOuter = BridgeModule('destinationOuter')
        ..addSubModule(destinationInner);

      final top = BridgeModule('top')
        ..addSubModule(sourceOuter)
        ..addSubModule(destinationOuter);

      sourceOuter.addInput('clk', null);
      top.pullUpPort(sourceOuter.port('clk'), newPortName: 'clk');

      void connect(PortReference sourcePort, PortReference destinationPort) {
        connectPorts(sourcePort, destinationPort,
            driverPathNewPortName: 'lane', receiverPathNewPortName: 'lane');
      }

      connect(source.port('bus[3:0]'), destination1.port('a'));
      connect(source.port('bus[3:0]'), destination2.port('b'));
      connect(source.port('bus[7:4]'), destination3.port('c'));

      for (final module in [sourceInner, sourceOuter]) {
        expect(module.outputs.keys, ['lane', 'lane_0']);
      }
      for (final module in [destinationInner, destinationOuter]) {
        expect(module.inputs.keys, ['lane', 'lane_0']);
      }

      await top.build();

      source.output('bus').put(0xa5);
      expect(destination1.input('a').value.toInt(), 0x5);
      expect(destination2.input('b').value.toInt(), 0x5);
      expect(destination3.input('c').value.toInt(), 0xa);
    });

    test('nested inout source fan-out reuses named receiver path', () async {
      final source = BridgeModule('source')
        ..createPort('io', PortDirection.inOut, width: 2);
      final destination1 = BridgeModule('destination1')
        ..createPort('a', PortDirection.input, width: 2);
      final destination2 = BridgeModule('destination2')
        ..createPort('b', PortDirection.input, width: 2);

      final sourceParent = BridgeModule('sourceParent')..addSubModule(source);
      final destinationParent = BridgeModule('destinationParent')
        ..addSubModule(destination1)
        ..addSubModule(destination2);

      final top = BridgeModule('top')
        ..addSubModule(sourceParent)
        ..addSubModule(destinationParent);

      sourceParent.addInput('clk', null);
      top.pullUpPort(sourceParent.port('clk'), newPortName: 'clk');

      connectPorts(source.port('io'), destination1.port('a'),
          receiverPathNewPortName: 'io');
      connectPorts(source.port('io'), destination2.port('b'),
          receiverPathNewPortName: 'io');

      expect(sourceParent.inOuts.keys, ['source_io']);
      expect(destinationParent.inputs.keys, ['io']);

      await top.build();

      source.inOut('io').put(2);
      expect(destination1.input('a').value.toInt(), 2);
      expect(destination2.input('b').value.toInt(), 2);
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
    test('explicit names respect interface-established receiver routes',
        () async {
      final matchingLeaf = BridgeModule('matchingLeaf')
        ..addInput('matchingInput', null);
      final aliasLeaf1 = BridgeModule('aliasLeaf1')
        ..addInput('aliasInput1', null);
      final aliasLeaf2 = BridgeModule('aliasLeaf2')
        ..addInput('aliasInput2', null);
      final matchingMid = BridgeModule('matchingMid')
        ..addSubModule(matchingLeaf);
      final aliasMid = BridgeModule('aliasMid')
        ..addSubModule(aliasLeaf1)
        ..addSubModule(aliasLeaf2);
      final interfaceLeaf = BridgeModule('interfaceLeaf')
        ..addInterface(MyPortInterface(),
            name: 'myIntf', role: PairRole.consumer);
      final upperMid = BridgeModule('upperMid')
        ..addSubModule(interfaceLeaf)
        ..addSubModule(matchingMid)
        ..addSubModule(aliasMid);
      final top = BridgeModule('top')
        ..addInput('myPort', null)
        ..addSubModule(upperMid);

      upperMid.pullUpInterface(interfaceLeaf.interface('myIntf'),
          newIntfName: 'myIntf');
      final establishedPathName = upperMid.inputs.keys.single;

      connectPorts(
          top.port('myPort'), upperMid.interface('myIntf').port('myIntfPort'));
      connectPorts(top.port('myPort'), matchingLeaf.port('matchingInput'),
          receiverPathNewPortName: establishedPathName);
      connectPorts(top.port('myPort'), aliasLeaf1.port('aliasInput1'),
          receiverPathNewPortName: 'alternate');
      connectPorts(top.port('myPort'), aliasLeaf2.port('aliasInput2'),
          receiverPathNewPortName: 'alternate');

      expect(upperMid.inputs.keys, [establishedPathName, 'alternate']);
      expect(matchingMid.inputs.keys, [establishedPathName]);
      expect(aliasMid.inputs.keys, ['alternate']);

      await top.build();

      top.input('myPort').put(1);
      expect(matchingLeaf.input('matchingInput').value.toInt(), 1);
      expect(aliasLeaf1.input('aliasInput1').value.toInt(), 1);
      expect(aliasLeaf2.input('aliasInput2').value.toInt(), 1);
      expect(interfaceLeaf.input('myIntf_myIntfPort').value.toInt(), 1);
    });

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
