// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// mi_test.dart
// Unit tests for MI (multiple instances).
//
// 2024 November
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('mi test', () async {
    final subPar1 = BridgeModule('subPar');
    final subPar2 = BridgeModule('subPar');

    final parA = BridgeModule('parA')..addSubModule(subPar1);
    final parB = BridgeModule('parB')..addSubModule(subPar2);

    final top = BridgeModule('top')
      ..addSubModule(parA)
      ..addSubModule(parB);

    subPar1.addOutput('myOut');
    subPar2.addOutput('myOut');

    top
      ..pullUpPort(subPar1.port('myOut'))
      ..pullUpPort(subPar2.port('myOut'));

    await top.build();

    final synthBuilder = SynthBuilder(top, SystemVerilogSynthesizer());

    // there should only be 4 module definitions
    expect(synthBuilder.synthesisResults.length, 4);
  });
}
