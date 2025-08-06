// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// par_b.dart
// Definition for ParB used in port_test.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

import 'intf_a.dart';

class ParBMod extends BridgeModule {
  late int paramA;
  ParBMod({this.paramA = 1, String instName = 'parB'})
      : super('parB', name: instName) {
    final inf1 = addInterface(
      IntfA(),
      name: 'inf1',
      role: PairRole.consumer,
      connect: false,
    );

    addInput('apple', inf1.interface.port('apple'), width: 4);
    inf1.interface.port('orange') <= addOutput('orange', width: 4);

    addInput('in1', inf1.interface.port('fp'));
    inf1.interface.port('fc') <= addOutput('fc');

    addOutput('global_reset_n_global_reset_n_rxdata');
  }
}
