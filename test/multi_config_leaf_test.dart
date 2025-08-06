// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// multi_config_leaf_test.dart
// Unit tests for multiple different parameterizations of the same leaf.
//
// 2024 November
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class MyLeaf extends BridgeModule {
  final bool asSvLeaf;

  MyLeaf(int myParam, {this.asSvLeaf = false})
      : super('MyLeaf',
            isSystemVerilogLeaf: asSvLeaf,
            reserveDefinitionName: true,
            instantiationParameters: {
              'MY_PARAM': myParam.toString(),
            }) {
    createParameter('MY_PARAM', '6');
    createPort('clk', PortDirection.input);
  }
}

class LeafWrapper extends BridgeModule {
  final bool svLeaf;

  LeafWrapper(int myParam, {this.svLeaf = false})
      : super('LeafWrapper', reserveDefinitionName: false) {
    final leaf = addSubModule(MyLeaf(myParam, asSvLeaf: svLeaf));
    pullUpPort(leaf.port('clk'), newPortName: 'clk');
  }
}

class TopModule extends BridgeModule {
  final bool svLeaves;

  TopModule({this.svLeaves = false}) : super('TopModule') {
    addSubModule(LeafWrapper(0, svLeaf: svLeaves));
    addSubModule(LeafWrapper(1, svLeaf: svLeaves));

    var idx = 0;
    for (final wrapper in subBridgeModules) {
      pullUpPort(wrapper.port('clk'), newPortName: 'clk$idx');
      idx++;
    }
  }
}

void main() {
  test('multiple parameterizations of same leaf works', () async {
    final mod = TopModule();
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, contains('module MyLeaf '));
    expect(sv, isNot(contains('module MyLeaf_0 ')));
    expect(sv, contains('parameter int MY_PARAM = 6'));

    expect(sv, contains('module LeafWrapper '));
    expect(sv, contains('module LeafWrapper_0 '));
    expect(sv, contains('MyLeaf #(.MY_PARAM(0)) MyLeaf(.clk(clk));'));
    expect(sv, contains('MyLeaf #(.MY_PARAM(1)) MyLeaf(.clk(clk));'));

    expect(sv, isNot(contains('*NONE*')));
  });

  test('multiple parameterizations of same leaf as SV leaf works', () async {
    final mod = TopModule(svLeaves: true);
    await mod.build();

    final sv = mod.generateSynth();

    expect(sv, isNot(contains('module MyLeaf ')));

    expect(sv, contains('module LeafWrapper '));
    expect(sv, contains('module LeafWrapper_0 '));
    expect(sv, contains('MyLeaf #(.MY_PARAM(0)) MyLeaf(.clk(clk));'));
    expect(sv, contains('MyLeaf #(.MY_PARAM(1)) MyLeaf(.clk(clk));'));

    expect(sv, isNot(contains('*NONE*')));
  });

  test('leaf sv module must have reserve definition name', () {
    expect(
      () => BridgeModule('testmod',
          isSystemVerilogLeaf: true, reserveDefinitionName: false),
      throwsA(isA<Exception>()),
    );
  });
}
