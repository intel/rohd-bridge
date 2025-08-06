// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// feedthrough_test.dart
// Unit tests for feedthroughs.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('Feedthrough exception', () async {
    // This is to make sure that the feedthrough cases are caught
    // This test must fail

    final top = BridgeModule('Top');

    final east = top.addSubModule(BridgeModule('east'));
    final west = top.addSubModule(BridgeModule('west'));

    east.createPort('x', PortDirection.input);
    west.createPort('x', PortDirection.input);

    east.createPort('y', PortDirection.output);
    west.createPort('y', PortDirection.output);

    var testPass1 = false;
    var testPass2 = false;
    try {
      connectPorts(east.port('x'), west.port('x'));
    } on Exception {
      testPass1 = true;
    }
    try {
      connectPorts(east.port('y'), west.port('y'));
    } on Exception {
      testPass2 = true;
    }

    expect(testPass1 && testPass2, true);
  });
}
