// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// connectivity_test.dart
// Unit tests for port and array connectivity.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  ///test for slicing
  test('Bit-sliced Connectivity', () async {
    final top = BridgeModule('top');
    final east = top.addSubModule(BridgeModule('east'))
      ..addInput('inPort_1', Logic(name: 'inPort_1', width: 32), width: 32)
      ..addInputArray('inPort_2', LogicArray([2, 2], 1), dimensions: [2, 2])
      ..addInputArray('east_array_in', Logic(name: 'east_array_in', width: 8),
          dimensions: [2, 2, 2])
      ..addInputArray(
          'east_array_in_1', Logic(name: 'east_array_in_1', width: 8),
          dimensions: [2, 2, 2]);

    final west = top.addSubModule(BridgeModule('west'))
      ..addOutputArray('west_array_out', dimensions: [2, 2, 2])
      ..addOutputArray('west_array_out_1', dimensions: [2, 2, 2])
      ..addOutput('outPort_1', width: 32)
      ..addOutput('outPort_2', width: 4);

///////////////////////////////////////////////////////////////////////////////////////
    east.addInputArray('east_btrs_apb_m_prdata_in', LogicArray([2, 2], 1),
        dimensions: [2, 2]);
    west.addOutput('west_btrs_apb_m_prdata_out', width: 4);
    connectPorts(west.port('west_btrs_apb_m_prdata_out[1:0]'),
        east.port('east_btrs_apb_m_prdata_in[1]'));
    connectPorts(west.port('west_btrs_apb_m_prdata_out[1:0]'),
        east.port('east_btrs_apb_m_prdata_in[0]'));
    west.output('west_btrs_apb_m_prdata_out').put('1010');
    expect(east.input('east_btrs_apb_m_prdata_in').value,
        equals(LogicValue.of('1010')));
///////////////////////////////////////////////////////////////////////////////////////

    connectPorts(west.port('west_array_out[0]'), east.port('east_array_in[0]'));
    connectPorts(west.port('west_array_out[1]'), east.port('east_array_in[1]'));
    west.output('west_array_out').put('10101010');
    expect(
        east.input('east_array_in').value, equals(LogicValue.of('10101010')));
///////////////////////////////////////////////////////////////////////////////////////

    connectPorts(west.port('outPort_1'), east.port('inPort_1'));
    west.output('outPort_1').put(LogicValue.one);
    expect(
        west.output('outPort_1').value, equals(east.input('inPort_1').value));
    connectPorts(west.port('west_array_out_1[0][1:0]'),
        east.port('east_array_in_1[0][1:0]'));
    connectPorts(west.port('west_array_out_1[1][1:0]'),
        east.port('east_array_in_1[1][1:0]'));
    west.output('west_array_out_1').put(LogicValue.one);
    expect(west.output('west_array_out_1').value,
        equals(east.input('east_array_in_1').value));
///////////////////////////////////////////////////////////////////////////////////////

    east.createPort('dummy', PortDirection.output);
    west.createPort('dummy1', PortDirection.output);
    top
      ..pullUpPort(west.port('dummy1'))
      ..pullUpPort(east.port('dummy'));

    east.output('dummy').put('1');
    expect(top.output('east_dummy').value.toInt(), equals(1));
    west.output('dummy1').put('1');
    expect(top.output('west_dummy1').value.toInt(), equals(1));
///////////////////////////////////////////////////////////////////////////////////////

    await top.build();
    top.generateSynth();
  });

  ///test for naming unification with subsets
  test('Naming Uniquification', () async {
    final top = BridgeModule('top');
    final east = top.addSubModule(BridgeModule('east'));
    final west = top.addSubModule(BridgeModule('west'));

    final e1 = east.addSubModule(BridgeModule('e1'));
    final e2 = east.addSubModule(BridgeModule('e2'));

    final w1 = west.addSubModule(BridgeModule('w1'));
    final w2 = west.addSubModule(BridgeModule('w2'));

    top.pullUpPort(w2.createPort('dummy', PortDirection.input));

    e1.addOutput('out_1', width: 32);
    e2.addOutput('out_1', width: 32);

    w1.addInputArray('in_1', Logic(name: 'in_1', width: 4), dimensions: [2, 2]);
    w2.addInputArray('in_1', Logic(name: 'in_1', width: 4), dimensions: [2, 2]);
    connectPorts(e1.port('out_1[1:0]'), w1.port('in_1[0][1:0]'));
    connectPorts(e2.port('out_1[3:2]'), w1.port('in_1[1][1:0]'));
    e1.output('out_1').put('10');
    expect(w1.input('in_1').value, equals(LogicValue.of('zz10')));
    e2.output('out_1').put('10zz');
    expect(w1.input('in_1').value, equals(LogicValue.of('1010')));
    ///////////////////////////////////////////////////////////////////////////////////////////
    w1.createPort('dummy', PortDirection.output, width: 8);
    e1.createPort('din', PortDirection.input, width: 8);
    ///////////////////////////////////////////////////////////////////////////////////////////
    top.pullUpPort(w1.port('dummy'));
    expect(top.outputs.keys, contains('w1_dummy'));
    ///////////////////////////////////////////////////////////////////////////////////////////
    connectPorts(w1.port('dummy[7:0]'), e1.port('din[7:0]'));
    top.output('w1_dummy').put('10101010');
    expect(e1.input('din').value, equals(LogicValue.of('10101010')));
    expect(w1.output('dummy').value, equals(LogicValue.of('10101010')));
    ///////////////////////////////////////////////////////////////////////////////////////////

    await top.build();
  });

  test('Slicing generates Violation of input/output rules', () async {
    final top = BridgeModule('top');
    final north = top.addSubModule(BridgeModule('north'));
    final east = north.addSubModule(BridgeModule('east'));
    final south = top.addSubModule(BridgeModule('south'));
    final west = south.addSubModule(BridgeModule('west'));

    east.addOutputArray('out_1', dimensions: [2, 2]);
    west.addInput('in_1', LogicArray([4], 1, name: 'in_1'), width: 4);

    east
      ..addInputArray('in1', LogicArray([7, 4], 1, name: 'in1'),
          dimensions: [7, 4])
      ..addInputArray('in2', LogicArray([7, 4], 1, name: 'in1'),
          dimensions: [7, 4]);
    west.addOutputArray('array_out', dimensions: [7, 4]);

    connectPorts(west.port('array_out[6]'), east.port('in1[0][3:0]'));
    connectPorts(west.port('array_out[5]'), east.port('in1[1][3:0]'));
    connectPorts(west.port('array_out[4]'), east.port('in1[2][3:0]'));
    connectPorts(west.port('array_out[3]'), east.port('in1[3][3:0]'));
    connectPorts(west.port('array_out[2][3:0]'), east.port('in1[4][3:0]'));
    connectPorts(west.port('array_out[1][3:0]'), east.port('in1[5][3:0]'));
    connectPorts(west.port('array_out[0][3:0]'), east.port('in1[6][3:0]'));
    west.output('array_out').put(LogicValue.filled(28, LogicValue.one));
    expect(
        east.input('in1').value, equals(LogicValue.filled(28, LogicValue.one)));

    connectPorts(west.port('array_out[6:0]'), east.port('in2'));
    expect(
        east.input('in2').value, equals(LogicValue.filled(28, LogicValue.one)));

    east.createPort('dummy', PortDirection.output);
    west.createPort('dummy1', PortDirection.output);
    top
      ..pullUpPort(east.port('dummy'))
      ..pullUpPort(west.port('dummy1'));

    await top.build();
  });
}
