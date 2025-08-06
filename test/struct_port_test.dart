// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// struct_port_test.dart
// Unit tests for struct port handling.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'dart:convert';

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

Map<String, dynamic> getModuleJson(
    {bool structIsInput = true, String modName = 'my_mod'}) {
  final dir = structIsInput ? 'in' : 'out';
  final jsonStr = '''
{
    "complexPortMemberToRange": {
        "struct_${dir}put": {
            "struct_${dir}put.byte0": "struct_${dir}put[15:8]",
            "struct_${dir}put.byte1": "struct_${dir}put[7:0]"
        }
    },
    "moduleParameters": {},
    "name": "$modName",
    "portList": [
        {
            "direction": "input",
            "fulltype": "logic",
            "name": "clk",
            "packedRanges": "",
            "type": "logic",
            "unpackedRanges": "",
            "width": "1"
        },
        {
            "direction": "input",
            "fulltype": "logic",
            "name": "reset_n",
            "packedRanges": "",
            "type": "logic",
            "unpackedRanges": "",
            "width": "1"
        },
        {
            "direction": "input",
            "fulltype": "logic",
            "name": "in1",
            "packedRanges": "",
            "type": "logic",
            "unpackedRanges": "",
            "width": "1"
        },
        {
            "direction": "input",
            "fulltype": "logic",
            "name": "in2",
            "packedRanges": "",
            "type": "logic",
            "unpackedRanges": "",
            "width": "1"
        },
        {
            "direction": "${dir}put",
            "fulltype": "mypkg::my_struct_t",
            "name": "struct_${dir}put",
            "packedRanges": "[15:0]",
            "type": "mypkg::my_struct_t",
            "unpackedRanges": "",
            "width": "16"
        },
        {
            "direction": "output",
            "fulltype": "logic",
            "name": "out1",
            "packedRanges": "",
            "type": "logic",
            "unpackedRanges": "",
            "width": "1"
        },
        {
            "direction": "output",
            "fulltype": "logic",
            "name": "out2",
            "packedRanges": "",
            "type": "logic",
            "unpackedRanges": "",
            "width": "1"
        }
    ]
}
''';
  return jsonDecode(jsonStr) as Map<String, dynamic>;
}

void main() {
  test('Struct port test', () async {
    final top = BridgeModule('soc');

    // final leaf1 = JsonModule(mod1, name: 'leaf1');
    final leaf1 = BridgeModule('my_mod2')
      ..addFromJson(getModuleJson(modName: 'my_mod2'));
    // final leaf2 = JsonModule(mod2, name: 'leaf2');
    final leaf2 = BridgeModule('my_mod')
      ..addFromJson(getModuleJson(structIsInput: false));

    top
      ..addSubModule(leaf1)
      ..addSubModule(leaf2)
      ..createPort('clk', PortDirection.input)
      ..createPort('reset_n', PortDirection.input);
    connectPorts(top.port('clk'), leaf1.port('clk'));
    connectPorts(top.port('clk'), leaf2.port('clk'));
    connectPorts(top.port('reset_n'), leaf1.port('reset_n'));
    connectPorts(top.port('reset_n'), leaf2.port('reset_n'));
    connectPorts(
        leaf2.port('struct_output.byte0'), leaf1.port('struct_input.byte1'));
    connectPorts(
        leaf2.port('struct_output.byte1'), leaf1.port('struct_input.byte0'));

    // byte0 is connected to byte1, each of which are 8 bits
    leaf2.output('struct_output').put(int.parse('AB12', radix: 16));
    // the ls8b should become ms8b and vice versa
    expect(leaf1.input('struct_input').value.toInt(),
        equals(int.parse('12AB', radix: 16)));

    await top.build();
    final sv = top.generateSynth();
    expect(sv, contains('logic [15:0] struct_input')); // may have _subset
    expect(sv, contains('logic [15:0] struct_output')); // may have _subset
  });
}
