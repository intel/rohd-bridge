// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// delayed_portmap_test.dart
// Unit tests for delayed port mapping.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class SimpleIntf extends PairInterface {
  SimpleIntf()
      : super(
          portsFromProvider: [
            Logic.port('fp'),
          ],
          portsFromConsumer: [
            Logic.port('fc'),
          ],
        );

  @override
  SimpleIntf clone() => SimpleIntf();
}

class SimpleIntf2 extends PairInterface {
  SimpleIntf2()
      : super(portsFromProvider: [
          Logic.port('fp1', 4),
          Logic.port('fp2', 8),
        ], portsFromConsumer: [
          Logic.port('fc1', 4),
          Logic.port('fc2', 8),
        ], commonInOutPorts: [
          LogicNet.port('cio1', 4),
          LogicNet.port('cio2', 8),
        ]);

  @override
  SimpleIntf2 clone() => SimpleIntf2();
}

BridgeModule leaf(String name, PairRole role) {
  final thisLeaf = BridgeModule(name)
    ..createPort('in1', PortDirection.input)
    ..createPort('out1', PortDirection.output)
    ..addInterface(SimpleIntf(), name: 'myIntf', role: role, connect: false);

  thisLeaf
    ..addPortMap(
        thisLeaf.port('in1'),
        thisLeaf
            .interface('myIntf')
            .port(role == PairRole.consumer ? 'fp' : 'fc'))
    ..addPortMap(
        thisLeaf.port('out1'),
        thisLeaf
            .interface('myIntf')
            .port(role == PairRole.consumer ? 'fc' : 'fp'));

  return thisLeaf;
}

void main() {
  test('interface portmap connected', () async {
    final top = BridgeModule('top');
    final leaf1 = leaf('leaf1', PairRole.consumer);
    final leaf2 = leaf('leaf2', PairRole.provider);

    top
      ..addSubModule(leaf1)
      ..addSubModule(leaf2);
    connectInterfaces(leaf1.interface('myIntf'), leaf2.interface('myIntf'));

    top.pullUpPort(leaf1.createPort('dummy', PortDirection.input));

    await top.build();

    expect(leaf1.interface('myIntf').portMaps.length, 2);
    expect(
        leaf1.interface('myIntf').portMaps.every((e) => e.isConnected), isTrue);

    leaf1.input('in1').put(1);
    expect(leaf2.output('out1').value.toInt(), 1);
    leaf2.input('in1').put(1);
    expect(leaf1.output('out1').value.toInt(), 1);
  });

  test('interface portmap discarded', () async {
    final top = BridgeModule('top');
    final leaf1 = leaf('leaf1', PairRole.consumer);

    top.addSubModule(leaf1);
    connectPorts(top.createPort('in1', PortDirection.input), leaf1.port('in1'));
    connectPorts(
        leaf1.port('out1'), top.createPort('out1', PortDirection.output));

    await top.build();

    expect(leaf1.interface('myIntf').portMaps.length, 2);
    expect(leaf1.interface('myIntf').portMaps.every((e) => !e.isConnected),
        isTrue);

    leaf1.input('in1').put(1);
    expect(top.input('in1').value.toInt(), 1);
    leaf1.output('out1').put(1);
    expect(top.output('out1').value.toInt(), 1);
  });

  test('interface portmap directly', () {
    final top = BridgeModule('top');
    final leaf1 = leaf('leaf1', PairRole.consumer);
    top.addSubModule(leaf1);

    final intf = leaf1.interface('myIntf');
    final pm =
        intf.addPortMap(intf.port('fp'), leaf1.port('in1'), connect: false);

    expect(pm.isConnected, isFalse);

    pm
      ..connect()
      ..connect(); // a second time to test double connect

    expect(pm.isConnected, isTrue);
  });

  group('port mapped interface connection', () {
    for (final (name, connectionFunc) in [
      (
        'connectUpTo',
        (InterfaceReference leafIntf, InterfaceReference topIntf) =>
            leafIntf.connectUpTo(topIntf),
      ),
      (
        'connectDownTo',
        (InterfaceReference leafIntf, InterfaceReference topIntf) =>
            topIntf.connectDownTo(leafIntf),
      ),
      ('connectInterfaces', connectInterfaces)
    ]) {
      group(name, () {
        test('simple', () async {
          final top = BridgeModule('top')
            ..createPort('tfp1', PortDirection.output, width: 4)
            ..createPort('tfp2', PortDirection.output, width: 8)
            ..createPort('tfc1', PortDirection.input, width: 4)
            ..createPort('tfc2', PortDirection.input, width: 8)
            ..createPort('tcio1', PortDirection.inOut, width: 4)
            ..createPort('tcio2', PortDirection.inOut, width: 8);

          final leaf = BridgeModule('leaf');
          top
            ..addSubModule(leaf)
            ..pullUpPort(leaf.createPort('dummy', PortDirection.input));

          final leafIntf = leaf.addInterface(SimpleIntf2(),
              name: 'myIntf', role: PairRole.provider);
          final topIntf = top.addInterface(SimpleIntf2(),
              name: 'myIntf', role: PairRole.provider, connect: false);

          expect(topIntf.internalInterface, isNull);

          // before connection
          topIntf
            ..addPortMap(topIntf.port('fp1'), top.port('tfp1'))
            ..addPortMap(topIntf.port('fc1'), top.port('tfc1'))
            ..addPortMap(topIntf.port('cio1'), top.port('tcio1'));

          connectionFunc(leafIntf, topIntf);

          // after connection
          topIntf
            ..addPortMap(topIntf.port('fp2'), top.port('tfp2'))
            ..addPortMap(topIntf.port('fc2'), top.port('tfc2'))
            ..addPortMap(topIntf.port('cio2'), top.port('tcio2'));

          await top.build();

          leafIntf.internalInterface!.port('fp1').put(0xa);
          expect(topIntf.interface.port('fp1').value.toInt(), 0xa);

          leafIntf.internalInterface!.port('fp2').put(0x5b);
          expect(topIntf.interface.port('fp2').value.toInt(), 0x5b);

          topIntf.interface.port('fc1').put(0x3);
          expect(leafIntf.internalInterface!.port('fc1').value.toInt(), 0x3);

          topIntf.interface.port('fc2').put(0x7e);
          expect(leafIntf.internalInterface!.port('fc2').value.toInt(), 0x7e);

          leafIntf.internalInterface!.port('cio1').put(0x1);
          expect(topIntf.interface.port('cio1').value.toInt(), 0x1);

          topIntf.interface.port('cio2').put(0x4);
          expect(leafIntf.internalInterface!.port('cio2').value.toInt(), 0x4);
        });

        test('simple consumer', () async {
          final top = BridgeModule('top')
            ..createPort('tfp1', PortDirection.input, width: 4)
            ..createPort('tfp2', PortDirection.input, width: 8)
            ..createPort('tfc1', PortDirection.output, width: 4)
            ..createPort('tfc2', PortDirection.output, width: 8)
            ..createPort('tcio1', PortDirection.inOut, width: 4)
            ..createPort('tcio2', PortDirection.inOut, width: 8);

          final leaf = BridgeModule('leaf');
          top
            ..addSubModule(leaf)
            ..pullUpPort(leaf.createPort('dummy', PortDirection.input));

          final leafIntf = leaf.addInterface(SimpleIntf2(),
              name: 'myIntf', role: PairRole.consumer);
          final topIntf = top.addInterface(SimpleIntf2(),
              name: 'myIntf', role: PairRole.consumer, connect: false);

          expect(topIntf.internalInterface, isNull);

          // before connection
          topIntf
            ..addPortMap(topIntf.port('fp1'), top.port('tfp1'))
            ..addPortMap(topIntf.port('fc1'), top.port('tfc1'))
            ..addPortMap(topIntf.port('cio1'), top.port('tcio1'));

          connectionFunc(leafIntf, topIntf);

          // after connection
          topIntf
            ..addPortMap(topIntf.port('fp2'), top.port('tfp2'))
            ..addPortMap(topIntf.port('fc2'), top.port('tfc2'))
            ..addPortMap(topIntf.port('cio2'), top.port('tcio2'));

          await top.build();

          topIntf.interface.port('fp1').put(0xa);
          expect(leafIntf.internalInterface!.port('fp1').value.toInt(), 0xa);

          topIntf.interface.port('fp2').put(0x5b);
          expect(leafIntf.internalInterface!.port('fp2').value.toInt(), 0x5b);

          leafIntf.internalInterface!.port('fc1').put(0x3);
          expect(topIntf.interface.port('fc1').value.toInt(), 0x3);

          leafIntf.internalInterface!.port('fc2').put(0x7e);
          expect(topIntf.interface.port('fc2').value.toInt(), 0x7e);

          topIntf.interface.port('cio1').put(0x1);
          expect(leafIntf.internalInterface!.port('cio1').value.toInt(), 0x1);

          leafIntf.internalInterface!.port('cio2').put(0x4);
          expect(topIntf.interface.port('cio2').value.toInt(), 0x4);
        });

        group('with slices', () {
          void checkSliceyAsProvider(BridgeModule top, BridgeModule leaf) {
            final leafIntf = leaf.interface('myIntf');
            final topIntf = top.interface('myIntf');

            final leafIntfIntf =
                leafIntf.internalInterface ?? leafIntf.interface;

            leafIntfIntf.port('fp1').put('x10x');
            expect(topIntf.interface.port('fp1').value,
                LogicValue.ofString('z10z'));
            expect(top.output('tfp1').value, LogicValue.ofString('zz10zz'));

            leafIntfIntf.port('fp2').put('xxxxx01x');
            expect(topIntf.interface.port('fp2').value,
                LogicValue.ofString('zzzzz01z'));
            expect(top.output('tfp2').value, LogicValue.ofString('01zz'));

            topIntf.interface.port('fc1').put('x11x');
            expect(leafIntfIntf.port('fc1').value, LogicValue.ofString('z11z'));

            topIntf.interface.port('fc2').put('xxxxx11x');
            expect(leafIntfIntf.port('fc2').value,
                LogicValue.ofString('zzzzz11z'));

            leafIntfIntf.port('cio1').put('x01x');
            expect(topIntf.interface.port('cio1').value,
                LogicValue.ofString('z01z'));
            expect(top.inOut('tcio1').value, LogicValue.ofString('zz01zz'));

            topIntf.interface.port('cio2').put('xxxxx10x');
            expect(leafIntfIntf.port('cio2').value,
                LogicValue.ofString('zzzzz10z'));
            expect(top.inOut('tcio2').value, LogicValue.ofString('10zz'));
          }

          void checkSliceyAsConsumer(BridgeModule top, BridgeModule leaf) {
            final leafIntf = leaf.interface('myIntf');
            final topIntf = top.interface('myIntf');

            final leafIntfIntf =
                leafIntf.internalInterface ?? leafIntf.interface;

            topIntf.interface.port('fp1').put('x10x');
            expect(leafIntfIntf.port('fp1').value, LogicValue.ofString('z10z'));
            expect(top.input('tfp1').value, LogicValue.ofString('zz10zz'));

            topIntf.interface.port('fp2').put('xxxxx01x');
            expect(leafIntfIntf.port('fp2').value,
                LogicValue.ofString('zzzzz01z'));
            expect(top.input('tfp2').value, LogicValue.ofString('01zz'));

            leafIntfIntf.port('fc1').put('x11x');
            expect(topIntf.interface.port('fc1').value,
                LogicValue.ofString('z11z'));

            leafIntfIntf.port('fc2').put('xxxxx11x');
            expect(topIntf.interface.port('fc2').value,
                LogicValue.ofString('zzzzz11z'));

            topIntf.interface.port('cio1').put('x01x');
            expect(
                leafIntfIntf.port('cio1').value, LogicValue.ofString('z01z'));
            expect(top.inOut('tcio1').value, LogicValue.ofString('zz01zz'));

            leafIntfIntf.port('cio2').put('xxxxx10x');
            expect(topIntf.interface.port('cio2').value,
                LogicValue.ofString('zzzzz10z'));
            expect(top.inOut('tcio2').value, LogicValue.ofString('10zz'));
          }

          group('slices on top only', () {
            void makeConnections(BridgeModule top, BridgeModule leaf) {
              final leafIntf = leaf.interface('myIntf');
              final topIntf = top.interface('myIntf');

              // before connection
              topIntf
                ..addPortMap(topIntf.port('fp1').slice(2, 1),
                    top.port('tfp1').slice(3, 2))
                ..addPortMap(topIntf.port('fc1').slice(2, 1),
                    top.port('tfc1').slice(3, 2))
                ..addPortMap(topIntf.port('cio1').slice(2, 1),
                    top.port('tcio1').slice(3, 2));

              connectionFunc(leafIntf, topIntf);

              // after connection
              topIntf
                ..addPortMap(topIntf.port('fp2').slice(2, 1),
                    top.port('tfp2').slice(3, 2))
                ..addPortMap(topIntf.port('fc2').slice(2, 1),
                    top.port('tfc2').slice(3, 2))
                ..addPortMap(topIntf.port('cio2').slice(2, 1),
                    top.port('tcio2').slice(3, 2));
            }

            test('as provider', () async {
              final top = BridgeModule('top')
                ..createPort('tfp1', PortDirection.output, width: 6)
                ..createPort('tfp2', PortDirection.output, width: 4)
                ..createPort('tfc1', PortDirection.input, width: 6)
                ..createPort('tfc2', PortDirection.input, width: 4)
                ..createPort('tcio1', PortDirection.inOut, width: 6)
                ..createPort('tcio2', PortDirection.inOut, width: 4);

              final leaf = BridgeModule('leaf');
              top
                ..addSubModule(leaf)
                ..pullUpPort(leaf.createPort('dummy', PortDirection.input));

              leaf.addInterface(SimpleIntf2(),
                  name: 'myIntf', role: PairRole.provider);
              top.addInterface(SimpleIntf2(),
                  name: 'myIntf', role: PairRole.provider, connect: false);

              makeConnections(top, leaf);

              await top.build();

              checkSliceyAsProvider(top, leaf);
            });

            test('as consumer', () async {
              final top = BridgeModule('top')
                ..createPort('tfp1', PortDirection.input, width: 6)
                ..createPort('tfp2', PortDirection.input, width: 4)
                ..createPort('tfc1', PortDirection.output, width: 6)
                ..createPort('tfc2', PortDirection.output, width: 4)
                ..createPort('tcio1', PortDirection.inOut, width: 6)
                ..createPort('tcio2', PortDirection.inOut, width: 4);

              final leaf = BridgeModule('leaf');
              top
                ..addSubModule(leaf)
                ..pullUpPort(leaf.createPort('dummy', PortDirection.input));

              leaf.addInterface(SimpleIntf2(),
                  name: 'myIntf', role: PairRole.consumer);
              top.addInterface(SimpleIntf2(),
                  name: 'myIntf', role: PairRole.consumer, connect: false);

              makeConnections(top, leaf);

              await top.build();

              checkSliceyAsConsumer(top, leaf);
            });
          });

          group('slices on top and leaf, with late binding', () {
            void makeConnections(BridgeModule top, BridgeModule leaf) {
              final leafIntf = leaf.interface('myIntf');
              final topIntf = top.interface('myIntf');

              // before connection
              leafIntf
                ..addPortMap(leafIntf.port('fc1').slice(2, 1),
                    leaf.port('lfc1').slice(3, 2),
                    connect: false)
                ..addPortMap(leafIntf.port('fp1').slice(2, 1),
                    leaf.port('lfp1').slice(3, 2))
                ..addPortMap(leafIntf.port('cio1').slice(2, 1),
                    leaf.port('lcio1').slice(3, 2));

              topIntf
                ..addPortMap(topIntf.port('fp1').slice(2, 1),
                    top.port('tfp1').slice(3, 2))
                ..addPortMap(topIntf.port('fc1').slice(2, 1),
                    top.port('tfc1').slice(3, 2))
                ..addPortMap(topIntf.port('cio1').slice(2, 1),
                    top.port('tcio1').slice(3, 2));

              connectionFunc(leafIntf, topIntf);

              // after connection
              topIntf
                ..addPortMap(topIntf.port('fp2').slice(2, 1),
                    top.port('tfp2').slice(3, 2))
                ..addPortMap(topIntf.port('fc2').slice(2, 1),
                    top.port('tfc2').slice(3, 2))
                ..addPortMap(topIntf.port('cio2').slice(2, 1),
                    top.port('tcio2').slice(3, 2));

              leafIntf
                  .addPortMap(leafIntf.port('fp2').slice(2, 1),
                      leaf.port('lfp2').slice(3, 2),
                      connect: false)
                  .connect();
              leafIntf
                ..addPortMap(leafIntf.port('fc2').slice(2, 1),
                    leaf.port('lfc2').slice(3, 2))
                ..addPortMap(leafIntf.port('cio2').slice(2, 1),
                    leaf.port('lcio2').slice(3, 2));
            }

            test('as provider', () async {
              final top = BridgeModule('top')
                ..createPort('tfp1', PortDirection.output, width: 6)
                ..createPort('tfp2', PortDirection.output, width: 4)
                ..createPort('tfc1', PortDirection.input, width: 6)
                ..createPort('tfc2', PortDirection.input, width: 4)
                ..createPort('tcio1', PortDirection.inOut, width: 6)
                ..createPort('tcio2', PortDirection.inOut, width: 4);

              final leaf = BridgeModule('leaf')
                ..createPort('lfp1', PortDirection.output, width: 6)
                ..createPort('lfp2', PortDirection.output, width: 4)
                ..createPort('lfc1', PortDirection.input, width: 6)
                ..createPort('lfc2', PortDirection.input, width: 4)
                ..createPort('lcio1', PortDirection.inOut, width: 6)
                ..createPort('lcio2', PortDirection.inOut, width: 4);

              top
                ..addSubModule(leaf)
                ..pullUpPort(leaf.createPort('dummy', PortDirection.input));

              leaf.addInterface(SimpleIntf2(),
                  name: 'myIntf', role: PairRole.provider, connect: false);
              top.addInterface(SimpleIntf2(),
                  name: 'myIntf', role: PairRole.provider, connect: false);

              makeConnections(top, leaf);

              await top.build();
              checkSliceyAsProvider(top, leaf);
            });

            test('as consumer', () async {
              final top = BridgeModule('top')
                ..createPort('tfp1', PortDirection.input, width: 6)
                ..createPort('tfp2', PortDirection.input, width: 4)
                ..createPort('tfc1', PortDirection.output, width: 6)
                ..createPort('tfc2', PortDirection.output, width: 4)
                ..createPort('tcio1', PortDirection.inOut, width: 6)
                ..createPort('tcio2', PortDirection.inOut, width: 4);

              final leaf = BridgeModule('leaf')
                ..createPort('lfp1', PortDirection.input, width: 6)
                ..createPort('lfp2', PortDirection.input, width: 4)
                ..createPort('lfc1', PortDirection.output, width: 6)
                ..createPort('lfc2', PortDirection.output, width: 4)
                ..createPort('lcio1', PortDirection.inOut, width: 6)
                ..createPort('lcio2', PortDirection.inOut, width: 4);

              top
                ..addSubModule(leaf)
                ..pullUpPort(leaf.createPort('dummy', PortDirection.input));

              leaf.addInterface(SimpleIntf2(),
                  name: 'myIntf', role: PairRole.consumer, connect: false);
              top.addInterface(SimpleIntf2(),
                  name: 'myIntf', role: PairRole.consumer, connect: false);

              makeConnections(top, leaf);

              await top.build();
              checkSliceyAsConsumer(top, leaf);
            });
          });
        });
      });
    }
  });

  test('split directions to submodules', () async {
    final top = BridgeModule('top')
      ..createPort('tfp', PortDirection.output, width: 2)
      ..createPort('tfc', PortDirection.input, width: 2);

    final leaves = [for (var i = 0; i < 2; i++) BridgeModule('leaf$i')]
      ..forEach(top.addSubModule);

    final tis = [
      for (var i = 0; i < 2; i++)
        top.addInterface(SimpleIntf(),
            name: 'ti$i', role: PairRole.provider, connect: false)
    ];

    final lis = [
      for (var i = 0; i < 2; i++)
        leaves[i].addInterface(SimpleIntf(),
            name: 'li', role: PairRole.provider, connect: false)
    ];

    // create port maps & connect interfaces
    for (var i = 0; i < 2; i++) {
      tis[i]
        ..addPortMap(tis[i].port('fp'), top.port('tfp')[i])
        ..addPortMap(tis[i].port('fc'), top.port('tfc')[i]);

      lis[i]
        ..addPortMap(lis[i].port('fp'),
            leaves[i].createPort('lfp', PortDirection.output))
        ..addPortMap(lis[i].port('fc'),
            leaves[i].createPort('lfc', PortDirection.input));

      connectInterfaces(tis[i], lis[i]);
    }

    await top.build();

    // make sure all the connections worked
    for (var i = 0; i < 2; i++) {
      leaves[i].output('lfp').put(1);
      expect(top.output('tfp').value[i], LogicValue.one);
      expect(tis[i].interface.port('fp').value, LogicValue.one);
      leaves[i].output('lfp').put(0);

      top.inputSource('tfc').put(1 << i);
      expect(leaves[i].input('lfc').value.toInt(), 1);
      expect(lis[i].interface.port('fc').value, LogicValue.one);
      top.inputSource('tfc').put(0);
    }
  });
}
