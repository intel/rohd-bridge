// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// build_and_generate_rtl_test.dart
// Tests to ensure that buildAndGenerateRTL works as expected.
//
// 2026 July 10
// Authors:
//   Max Korbel <max.korbel@intel.com>

import 'dart:io';

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('uses synthesis order and uniquified names for RTL files', () async {
    final output = await Directory.systemTemp.createTemp('rohd_bridge_rtl_');
    addTearDown(() => output.delete(recursive: true));

    final leaf8 = BridgeModule(
      'leaf',
      name: 'leaf8',
      reserveDefinitionName: false,
    )..createPort('data', PortDirection.output, width: 8);

    final leaf16 = BridgeModule(
      'leaf',
      name: 'leaf16',
      reserveDefinitionName: false,
    )..createPort('data', PortDirection.output, width: 16);

    final top = BridgeModule('aaa_top')
      ..addSubModule(leaf8)
      ..addSubModule(leaf16)
      ..pullUpPort(leaf8.port('data'))
      ..pullUpPort(leaf16.port('data'));

    await top.buildAndGenerateRTL(outputPath: output.path);

    final filelist = await File('${output.path}/filelist.f').readAsLines();

    expect(
      filelist,
      ['./rtl/leaf.sv', './rtl/leaf_0.sv', './rtl/aaa_top.sv'],
    );
    expect(File('${output.path}/rtl/leaf_0.sv').existsSync(), isTrue);
  });

  test('uses the provided synthesizer configuration', () async {
    final output = await Directory.systemTemp.createTemp('rohd_bridge_rtl_');
    addTearDown(() => output.delete(recursive: true));

    final top = BridgeModule('top')
      ..createPort('data', PortDirection.input, width: 8);

    await top.buildAndGenerateRTL(
      outputPath: output.path,
      synthesizerConfiguration: const SystemVerilogSynthesizerConfiguration(
        portObjectType: SystemVerilogPortType.implicit,
        portDataType: SystemVerilogPortType.implicit,
      ),
    );

    final rtl = await File('${output.path}/rtl/top.sv').readAsString();

    expect(rtl, contains('input [7:0] data'));
    expect(rtl, isNot(contains('input wire logic [7:0] data')));
  });
}
