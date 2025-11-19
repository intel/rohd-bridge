// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// pretty_test.dart
// Unit tests to make sure specific scenarios look pretty in generated SV.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('non-array multi-bit full connection clean', () async {
    final top = BridgeModule('top');
    final east = top.addSubModule(BridgeModule('east'));
    final west = top.addSubModule(BridgeModule('west'));

    top.addInput('clk', null);
    east.addInput('clk', null);
    connectPorts(top.port('clk'), east.port('clk'));

    east.addOutput('myOutput', width: 4);
    west.addInput('myInput', null, width: 4);
    connectPorts(east.port('myOutput'), west.port('myInput'));

    await top.build();
    final sv = top.generateSynth();

    expect(sv, contains('''
logic [3:0] myInput;
east  east(.clk(clk),.myOutput(myInput));
west  west(.myInput(myInput));
'''));
  });

  test('array full connection clean', () async {
    final top = BridgeModule('top');
    final east = top.addSubModule(BridgeModule('east'));
    final west = top.addSubModule(BridgeModule('west'));

    top.addInput('clk', null);
    east.addInput('clk', null);
    connectPorts(top.port('clk'), east.port('clk'));

    east.addOutputArray('myOutput', dimensions: [4]);
    west.addInputArray('myInput', null, dimensions: [4]);
    connectPorts(east.port('myOutput'), west.port('myInput'));

    await top.build();
    final sv = top.generateSynth();

    expect(sv, contains('''
logic [3:0] myInput;
east  east(.clk(clk),.myOutput(myInput));
west  west(.myInput(myInput));'''));
  });

  test('multiple single ports to one bus', () async {
    final top = BridgeModule('top')..addInput('clk', null);

    const numBits = 4;

    final aggregator = top.addSubModule(BridgeModule('aggregator')
      ..addInput('merged_bits', null, width: numBits)
      ..addInput('clk', null));

    connectPorts(top.port('clk'), aggregator.port('clk'));

    final leaves = [
      for (var i = 0; i < numBits; i++)
        top.addSubModule(BridgeModule('leaf$i')..addOutput('out_bit'))
    ];

    for (var i = 0; i < numBits; i++) {
      connectPorts(
          leaves[i].port('out_bit'), aggregator.port('merged_bits[$i]'));
    }

    await top.build();
    final sv = top.generateSynth();

    expect(
        sv,
        contains('aggregator(.merged_bits(({'
            'merged_bits_subset[3],'
            'merged_bits_subset[2],'
            'merged_bits_subset[1],'
            'merged_bits_subset[0]'
            '})),.clk(clk));'));
    expect(sv, contains('leaf1  leaf1(.out_bit(merged_bits_subset[1]));'));
  });

  test('unconnected ports left unconnected', () async {
    final top = BridgeModule('top');
    final modA = top.addSubModule(BridgeModule('modA')
      ..addInput('in_port', null)
      ..addOutput('out_port'));
    top.pullUpPort(modA.port('in_port'));

    await top.build();

    final sv = top.generateSynth();

    expect(sv, contains('modA(.in_port(modA_in_port),.out_port());'));
  });
}
