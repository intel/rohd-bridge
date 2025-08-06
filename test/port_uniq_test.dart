// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_uniq_test.dart
// Unit tests for port uniqueness and renaming.
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
            Logic.port('logicalName1'),
          ],
          portsFromConsumer: [
            Logic.port('logicalName2'),
          ],
        );

  @override
  SimpleIntf clone() => SimpleIntf();
}

void main() {
  test('simple phy port rename', () async {
    final leaf = BridgeModule('leaf')
      ..createPort('physicalName1', PortDirection.input)
      ..createPort('physicalName2', PortDirection.output)
      ..addInterface(SimpleIntf(),
          name: 'myIntf', role: PairRole.consumer, connect: false);

    leaf
      ..addPortMap(
        leaf.port('physicalName1'),
        leaf.interface('myIntf').port('logicalName1'),
      )
      ..addPortMap(
        leaf.port('physicalName2'),
        leaf.interface('myIntf').port('logicalName2'),
      );

    final mid = BridgeModule('mid')..addSubModule(leaf);

    final top = BridgeModule('top')
      ..addSubModule(mid)
      ..pullUpInterface(
        leaf.interface('myIntf'),
        portUniquify: (logical, physical) => '${logical}_asdf_$physical',
      );

    await top.build();

    expect(mid.inputs.keys, contains('logicalName1_asdf_physicalName1'));
    expect(mid.outputs.keys, contains('logicalName2_asdf_physicalName2'));
    expect(top.inputs.keys, contains('logicalName1_asdf_physicalName1'));
    expect(top.outputs.keys, contains('logicalName2_asdf_physicalName2'));

    top.input('logicalName1_asdf_physicalName1').put('1');
    expect(leaf.input('physicalName1').value.toInt(), 1);

    top.output('logicalName2_asdf_physicalName2').put('1');
    expect(leaf.output('physicalName2').value.toInt(), 1);

    expect(leaf.parent, mid);
    expect(mid.parent, top);
  });

  test('pull up a pulled up interface', () async {
    final leaf = BridgeModule('leaf')
      ..createPort('physicalName1', PortDirection.input)
      ..createPort('physicalName2', PortDirection.output)
      ..addInterface(SimpleIntf(),
          name: 'myIntf', role: PairRole.consumer, connect: false);

    leaf
      ..addPortMap(
        leaf.port('physicalName1'),
        leaf.interface('myIntf').port('logicalName1'),
      )
      ..addPortMap(
        leaf.port('physicalName2'),
        leaf.interface('myIntf').port('logicalName2'),
      );

    final mid = BridgeModule('mid')
      ..addSubModule(leaf)
      ..pullUpInterface(leaf.interface('myIntf'),
          portUniquify: (logical, physical) => '${logical}_xyz_$physical')
      ..renamePort('logicalName1_xyz_physicalName1',
          'logicalName1_xyz_physicalName1Renamed');

    final top = BridgeModule('top')
      ..addSubModule(mid)
      ..pullUpInterface(
        mid.interface('myIntf'),
        portUniquify: (logical, physical) => '${logical}_asdf_$physical',
      );

    await top.build();

    expect(mid.inputs.keys, contains('logicalName1_xyz_physicalName1'));
    expect(mid.outputs.keys, contains('logicalName2_xyz_physicalName2'));
    expect(top.inputs.keys,
        contains('logicalName1_asdf_logicalName1_xyz_physicalName1Renamed'));
    expect(top.outputs.keys,
        contains('logicalName2_asdf_logicalName2_xyz_physicalName2'));

    top
        .input('logicalName1_asdf_logicalName1_xyz_physicalName1Renamed')
        .put('1');
    expect(leaf.input('physicalName1').value.toInt(), 1);

    top.output('logicalName2_asdf_logicalName2_xyz_physicalName2').put('1');
    expect(leaf.output('physicalName2').value.toInt(), 1);

    expect(leaf.parent, mid);
    expect(mid.parent, top);
  });
}
