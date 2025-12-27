// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rb_general_utils_test.dart
// Tests for general utils.
//
// 2024 July
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'dart:convert';
import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('Get Int test', () {
    const binVal = "12'b111010100011";
    const hexVal = "12'hABC";
    const intVal = "12'd3445";
    const noVal = 'anything';

    final binVal2Int = BridgeModuleFromJson.getInt(binVal);
    final hexVal2Int = BridgeModuleFromJson.getInt(hexVal);
    final intVal2Int = BridgeModuleFromJson.getInt(intVal);
    final noVal2Int = BridgeModuleFromJson.getInt(noVal, asIsIfUnparsed: true);

    expect(noVal2Int, equals('anything'));
    expect(hexVal2Int, equals(BigInt.from(2748)));
    expect(intVal2Int, equals(BigInt.from(3445)));
    expect(binVal2Int, equals(BigInt.from(3747)));
  });

  test('Create and get params test', () {
    const parameters = {
      'paramA': {
        'type': 'int',
        'value': '5',
        'resolve': 'user',
        'ranges': '[7:0]'
      }
    };
    final mod = BridgeModule('modA')..addParametersFromJson(parameters);
    final expectedParams = {'paramA': '5'};

    expect(mod.instantiationParameters, equals(expectedParams));
    expect(mod.instantiationParameters.length, 1);
    expect(mod.instantiationParameters['paramA'], equals('5'));
  });

  test('Create ports from json', () {
    final json = [
      {'direction': 'input', 'packedRanges': '[5:0]', 'name': 'portA'},
      {'direction': 'output', 'packedRanges': '', 'name': 'portB'}
    ];
    final mod = BridgeModule('modA')..addPortsFromJson(json, {});
    expect(mod.inputs.length, 1);
    expect(mod.input('portA').width, equals(6));
    expect(mod.outputs.length, 1);
    expect(mod.output('portB').width, equals(1));
  });

  test('Create array ports from json', () {
    final json = [
      {
        'name': 'portA',
        'direction': 'input',
        'packedRanges': '[5:0][8:0][1:0]',
      },
      {
        'name': 'portB',
        'direction': 'output',
        'packedRanges': '[3:0][6:0]',
        'unpackedRanges': '[2:0]'
      },
    ];
    final mod = BridgeModule('modA')..addPortsFromJson(json, {});

    expect(mod.inputs.length, 1);
    final portA = mod.input('portA') as LogicArray;
    expect(portA.dimensions.length, 2);
    expect(portA.dimensions[0], 6);
    expect(portA.dimensions[1], 9);
    expect(portA.elementWidth, 2);
    expect(portA.numUnpackedDimensions, 0);

    expect(mod.outputs.length, 1);
    final portB = mod.output('portB') as LogicArray;
    expect(portA.dimensions.length, 2);
    expect(portB.dimensions[0], 3);
    expect(portB.dimensions[1], 4);
    expect(portB.elementWidth, 7);
    expect(portB.numUnpackedDimensions, 1);
  });

  test('Create unpacked 1-bit elem ports from json', () {
    final json = [
      {
        'name': 'portA',
        'direction': 'input',
        'packedRanges': '',
        'unpackedRanges': '[5:0][8:0]',
      },
      {
        'name': 'portB',
        'direction': 'output',
        'packedRanges': '',
        'unpackedRanges': '[2:0]',
      },
    ];
    final mod = BridgeModule('modA')..addPortsFromJson(json, {});

    expect(mod.inputs.length, 1);
    final portA = mod.input('portA') as LogicArray;
    expect(portA.dimensions.length, 2);
    expect(portA.dimensions[0], 6);
    expect(portA.dimensions[1], 9);
    expect(portA.elementWidth, 1);
    expect(portA.numUnpackedDimensions, 2);

    expect(mod.outputs.length, 1);
    final portB = mod.output('portB') as LogicArray;
    expect(portB.dimensions.length, 1);
    expect(portB.dimensions[0], 3);
    expect(portB.elementWidth, 1);
    expect(portB.numUnpackedDimensions, 1);
  });

  test('Create ports from json with unpacked', () async {
    final json = [
      {
        'direction': 'input',
        'packedRanges': '[5:0]',
        'unpackedRanges': '[5:0]',
        'name': 'portA'
      },
      {
        'direction': 'output',
        'packedRanges': '',
        'unpackedRanges': '[5:0]',
        'name': 'portB'
      }
    ];
    final mod = BridgeModule('modA')..addPortsFromJson(json, {});
    expect(mod.inputs.length, 1);
    expect(mod.inputs['portA']!.width, equals(36));
    expect((mod.inputs['portA']! as LogicArray).numUnpackedDimensions, 1);
    expect(mod.outputs.length, 1);
    expect(mod.outputs['portB']!.width, equals(6));

    await mod.build();
    final sv = mod.generateSynth();
    expect(sv, contains('input logic [5:0] portA [5:0]'));
    expect(sv, contains('output logic portB [5:0]'));
  });

  test('Process input file test (json from xml)', () {
    final top = BridgeModule.fromJson(
        jsonDecode(File('test/integration_test/modA.json').readAsStringSync())
            as Map<String, dynamic>);

    expect(top.inputs.length, equals(6));
    expect(top.outputs.length, equals(4));
  });

  test('Process input file test (json from sv)', () {
    final myModule = BridgeModule.fromJson(jsonDecode(
            File('test/test_collaterals/myModule.json').readAsStringSync())
        as Map<String, dynamic>);
    expect(myModule.inputs.length, equals(1));
    expect(myModule.outputs.length, equals(1));
    expect(myModule.input('portA').width, equals(6));
    expect(myModule.output('portD').width, equals(11));
    expect(myModule.definitionParameters.length, equals(2));
    expect(myModule.instantiationParameters['paramA'], equals('5'));
    expect(myModule.instantiationParameters['paramB'], equals('10'));
  });

  test(
      'Process input file test (json from sv) with param overrides and defines',
      () {
    final myModule = BridgeModule.fromJson(jsonDecode(
        File('test/test_collaterals/myModule_paramA7_paramB12.json')
            .readAsStringSync()) as Map<String, dynamic>);
    expect(myModule.inputs.length, equals(3));
    expect(myModule.outputs.length, equals(3));
    expect(myModule.input('portA').width, equals(8));
    expect(myModule.input('portB').width, equals(13));
    expect(myModule.output('portC').width, equals(8));
    expect(myModule.output('portD').width, equals(13));
    expect(myModule.input('portE').width, equals(13));
    expect(myModule.output('portF').width, equals(8));
    expect(myModule.definitionParameters.length, equals(2));
    expect(myModule.instantiationParameters['paramA'], equals('7'));
    expect(myModule.instantiationParameters['paramB'], equals('12'));
  });

  // test('get port name and range', () async {
  //   const portName = 'portA[5:0]';
  //   const portName2 = 'portB';
  //   const portName3 = 'portC[5:0][3:0]';

  //   final nameRange = getPortNameAndRange(portName);
  //   final nameRange2 = getPortNameAndRange(portName2);
  //   final nameRange3 = getPortNameAndRange(portName3);

  //   expect(nameRange.name, equals('portA'));
  //   expect(nameRange.range, equals('[5:0]'));
  //   expect(nameRange2.name, equals('portB'));
  //   expect(nameRange2.range, equals(''));
  //   expect(nameRange3.name, equals('portC'));
  //   expect(nameRange3.range, equals('[5:0][3:0]'));
  // });
}
