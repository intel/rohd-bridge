// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// json_module_test.dart
// Unit tests for `BridgeModule.ofJson`.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('param width parsing', () {
    test('simple int', () {
      final mod = BridgeModule.fromJson({
        'name': 'testmod',
        'moduleParameters': {
          'param1': {
            'type': 'int',
            'value': '5',
            'packedRanges': '',
            'dataType': 'logic',
            'resolve': 'user',
          },
        },
      });

      expect(
          mod.definitionParameters.firstWhere((e) => e.name == 'param1').type,
          'int');
    });

    test('single bit', () {
      final mod = BridgeModule.fromJson({
        'name': 'testmod',
        'moduleParameters': {
          'param1': {
            'type': 'bit',
            'value': '5',
            'packedRanges': '[0:0]',
            'dataType': 'logic',
            'resolve': 'user',
          },
        },
      });

      expect(
          mod.definitionParameters.firstWhere((e) => e.name == 'param1').type,
          'bit[0:0]');
    });

    test('multiple bits', () {
      final mod = BridgeModule.fromJson({
        'name': 'testmod',
        'moduleParameters': {
          'param1': {
            'type': 'bit',
            'value': "8'd100",
            'packedRanges': '[7:0]',
            'dataType': 'logic',
            'resolve': 'user',
          },
        },
      });

      expect(
          mod.definitionParameters.firstWhere((e) => e.name == 'param1').type,
          'bit[7:0]');
    });
  });

  group('resolve', () {
    test('immediate is omitted', () {
      final mod = BridgeModule.fromJson({
        'name': 'testmod',
        'moduleParameters': {
          'param1': {
            'type': 'int',
            'value': '5',
            'packedRanges': '',
            'dataType': 'logic',
            'resolve': 'immediate',
          },
        },
      });

      expect(mod.definitionParameters, isEmpty);
    });

    test('user is included', () {
      final mod = BridgeModule.fromJson({
        'name': 'testmod',
        'moduleParameters': {
          'param1': {
            'type': 'int',
            'value': '5',
            'packedRanges': '',
            'dataType': 'logic',
            'resolve': 'user',
          },
        },
      });

      expect(mod.definitionParameters, isNotEmpty);
      expect(mod.definitionParameters.first.name, 'param1');
    });
  });
}
