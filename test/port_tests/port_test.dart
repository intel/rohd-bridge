// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_test.dart
// Unit tests for port and interface behavior in port tests.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'dart:io';

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

import 'par_a.dart';
import 'par_b.dart';

void main() {
  test('ports checking', () async {
    final top = BridgeModule('Top');

    final east = BridgeModule('east');
    top.addSubModule(east);

    final west = BridgeModule('west');
    top.addSubModule(west);

    final parA = ParAMod();
    final parB = ParBMod();

    final east1 = BridgeModule('east1');
    final west1 = BridgeModule('west1');

    east.addSubModule(east1);
    west.addSubModule(west1);

    east1.addSubModule(parA);
    west1.addSubModule(parB);

    // top.connectInterface(parB, 'inf1', parA, 'inf1');

    east.pullUpInterface(parA.interface('inf1'), newIntfName: 'parA_intf1');
    west.pullUpInterface(parB.interface('inf1'), newIntfName: 'parB_intf1');
    connectInterfaces(
        east.interface('parA_intf1'), west.interface('parB_intf1'));

    parA.createPort('in', PortDirection.input);
    top.pullUpPort(parA.port('in'));

    parA.createPort('dummy', PortDirection.output, width: 8);
    parB.createPort('din', PortDirection.input, width: 8);

    connectPorts(parA.port('dummy[7:0]'), parB.port('din[7:0]'));
    connectPorts(parB.port('global_reset_n_global_reset_n_rxdata'),
        parA.port('bpk_pmode_val[1]'));

    parA.createPort('in1', PortDirection.input, width: 8);
    top.createPort('in1', PortDirection.input, width: 8);
    connectPorts(top.port('in1[7:0]'), parA.port('in1[7:0]'));

    const outPath = 'tmp_test/newChanges';
    await top.buildAndGenerateRTL(outputPath: outPath);

    expect(top.subModules, contains(east));
    expect(top.subModules, contains(west));
    expect(east.subModules, contains(east1));

    // clean up
    Directory(outPath).deleteSync(recursive: true);
  });
}
