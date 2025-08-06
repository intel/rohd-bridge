// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// intf_a.dart
// Interface definition for IntfA used in port_test.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

class IntfA extends PairInterface {
  final int paramA;

  IntfA({this.paramA = 1}) : super() {
    setPorts([Logic.port('fc', paramA)], [PairDirection.fromConsumer]);
    setPorts([Logic.port('fp', paramA)], [PairDirection.fromProvider]);
    setPorts([Logic.port('apple', 4), Logic.port('orange', 4)]);
  }

  @override
  IntfA clone() => IntfA(paramA: paramA);
}
