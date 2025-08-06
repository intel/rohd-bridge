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
}
