// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rename_test.dart
// Unit tests for port renaming and pull up.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('port renaming test at partition for a pull up', () async {
    final top = BridgeModule('top');
    final north = top.addSubModule(BridgeModule('north'));
    final east = north.addSubModule(BridgeModule('east'))
      ..createPort('apple', PortDirection.input, width: 8);
    north
      ..pullUpPort(east.port('apple'))
      ..renamePort('east_apple', 'notApple');

    top.pullUpPort(north.port('notApple'), newPortName: 'notApple');

    await top.build();
    top.input('notApple').put('10101010');
    expect(170, east.input('apple').value.toInt());
  });

  test('port renaming test with connectPorts', () async {
    final top = BridgeModule('top');
    final north = top.addSubModule(BridgeModule('north'));
    final east = north.addSubModule(BridgeModule('east'));

    final south = top.addSubModule(BridgeModule('south'));
    final west = south.addSubModule(BridgeModule('west'));

    east.createPort('apple', PortDirection.input, width: 8);
    west.createPort('orange', PortDirection.output, width: 8);

    east.renamePort('apple', 'orange');
    west.renamePort('orange', 'apple');

    var failCreatePort = false;
    try {
      east.createPort('orange', PortDirection.input, width: 8);
    } on Exception {
      failCreatePort = true;
    }

    var multipleRenameFailure = false;
    try {
      east.renamePort('orange', 'whatever');
    } on Exception {
      multipleRenameFailure = true;
    }

    connectPorts(west.port('apple'), east.port('orange'));
    top.pullUpPort(west.port('apple'));

    await top.build();
    top.output('west_orange').put('10101010');
    expect(170, east.input('apple').value.toInt());
    expect(170, west.output('orange').value.toInt());
    expect(failCreatePort, true);
    expect(multipleRenameFailure, true);
  });

  test('port renaming test with connectPorts on a subset of renamed ports',
      () async {
    final top = BridgeModule('top');
    final north = top.addSubModule(BridgeModule('north'));
    final east = north.addSubModule(BridgeModule('east'));

    final south = top.addSubModule(BridgeModule('south'));
    final west = south.addSubModule(BridgeModule('west'));

    east.createPort('apple', PortDirection.input, width: 8);
    west.createPort('orange', PortDirection.output, width: 8);

    east.renamePort('apple', 'orange');
    west.renamePort('orange', 'apple');

    var failCreatePort = false;
    try {
      east.createPort('orange', PortDirection.input, width: 8);
    } on Exception {
      failCreatePort = true;
    }

    var multipleRenameFailure = false;
    try {
      east.renamePort('orange', 'whatever');
    } on Exception {
      multipleRenameFailure = true;
    }

    connectPorts(west.port('apple[0]'), east.port('orange[0]'));
    connectPorts(west.port('apple[1]'), east.port('orange[1]'));
    connectPorts(west.port('apple[2]'), east.port('orange[2]'));
    connectPorts(west.port('apple[3]'), east.port('orange[3]'));
    connectPorts(west.port('apple[4]'), east.port('orange[4]'));
    connectPorts(west.port('apple[5]'), east.port('orange[5]'));
    connectPorts(west.port('apple[6]'), east.port('orange[6]'));
    connectPorts(west.port('apple[7]'), east.port('orange[7]'));

    top.pullUpPort(west.port('apple'));

    await top.build();
    top.output('west_orange').put('10101010');
    expect(170, east.input('apple').value.toInt());
    expect(170, west.output('orange').value.toInt());
    expect(failCreatePort, true);
    expect(multipleRenameFailure, true);
  });
}
