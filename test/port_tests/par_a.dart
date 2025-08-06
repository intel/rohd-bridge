// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// par_a.dart
// Definition for ParA used in port_test.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

import 'intf_a.dart';

class ParAMod extends BridgeModule {
  late int paramA;
  ParAMod({this.paramA = 1, String instName = 'parA'})
      : super('parA', name: instName) {
    final inf1 = addInterface(
      IntfA(),
      name: 'inf1',
      role: PairRole.provider,
      connect: false,
    );

    addInput('bpk_pmode_val', Logic(name: 'bpk_pmode_val', width: 7 - 0 + 1),
        width: 7 - 0 + 1);

    addOutput('apple', width: 8);

    addPortMap(port('apple[3:0]'), inf1.port('apple'));

    addInput('orange', Logic(name: 'orange', width: 8), width: 8);
    addPortMap(port('orange[3:0]'), inf1.port('orange'));

    addOutputArray('out1', dimensions: [5, 1]);
    addPortMap(port('out1[1]'), inf1.port('fp'));

    addInput('fc', Logic(name: 'fc', width: 8), width: 8);
    addPortMap(port('fc[0:0]'), inf1.port('fc'));
  }
}
