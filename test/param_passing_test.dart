// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// param_passing_test.dart
// Unit tests for pass-through SystemVerilog parameters.
//
// 2024 June 27
// Author:
//   Shankar Sharma <shankar.sharma@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('passthrough params custom system verilog', () async {
    final top = BridgeModule('soc');
    final par = top.addSubModule(BridgeModule('par'));
    final leaf1 = par.addSubModule(BridgeModule('leaf1'));
    final leaf2 = par.addSubModule(BridgeModule('leaf2'));

    leaf1
      ..createParameter('A', '10')
      ..createParameter('B', '5')
      ..createParameter('C', '15');
    leaf2
      ..createParameter('B', '5')
      ..createParameter('C', '16')
      ..createParameter('D', '20');

    top
      ..pullUpParameter(leaf1, 'A')
      // parameter B will be merged since it has the same value: 5
      ..pullUpParameter(leaf1, 'B')
      ..pullUpParameter(leaf2, 'B')
      // parameter C will not be merged since the values are different: 15!=16
      ..pullUpParameter(leaf1, 'C')
      ..pullUpParameter(leaf2, 'C', newParamName: 'CC')
      ..pullUpParameter(leaf2, 'D');

    leaf1.addInput('x', Logic());
    leaf2.addOutput('x');

    connectPorts(leaf2.port('x'), leaf1.port('x'));
    top.pullUpPort(leaf2.port('x'));

    leaf1.createParameter('paramx', '15', type: '[15:0]');
    leaf2.createParameter('paramx', '15', type: '[15:0]');

    leaf1.overrideParameter('paramx', '20');
    leaf2.overrideParameter('paramx', '20');

    top
      ..pullUpParameter(leaf1, 'paramx', newParamName: 'paramY')
      ..pullUpParameter(leaf2, 'paramx', newParamName: 'paramY');

    await top.build();

    final sv = top.generateSynth();
    expect(
        'par #(.A(A),.B(B),.C(C),.CC(CC),.D(D),.paramY(paramY)) '
        'par(.leaf2_x(leaf2_x));',
        sv.contains);
    expect('parameter [15:0] paramY = 20', sv.contains);
    expect('parameter int CC = 16,', sv.contains);
    expect('leaf2 #(.B(B),.C(CC),.D(D),.paramx(paramY)) leaf2(.x', sv.contains);
    expect('leaf1 #(.A(A),.B(B),.C(C),.paramx(paramY)) leaf1(.x', sv.contains);
  });

  test('localparam test', () {
    final leaf1 = BridgeModule('modA')
      ..addFromJson(
          jsonDecode(File('test/integration_test/modA.json').readAsStringSync())
              as Map<String, dynamic>);

    expect(leaf1.instantiationParameters.keys, isNot(contains('myLocalParam')));
    expect(leaf1.instantiationParameters.keys, contains('paramA'));
    expect(leaf1.instantiationParameters.keys, contains('paramB'));
  });

  test('inst param not a def param throws error', () async {
    final mod = BridgeModule(
      'testmod',
      instantiationParameters: {'INST_PARAM': '5'},
      definitionParameters: [
        const SystemVerilogParameterDefinition(
          'DEF_PARAM',
          defaultValue: '10',
          type: 'int',
        )
      ],
    )..createPort('clk', PortDirection.input);

    final parentMod = BridgeModule('parent')
      ..addSubModule(mod)
      ..pullUpPort(mod.port('clk'));

    await parentMod.build();

    expect(parentMod.generateSynth, throwsA(isA<Exception>()));
  });
}
