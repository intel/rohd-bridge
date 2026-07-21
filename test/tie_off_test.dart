// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// tie_off_test.dart
// Tests to ensure we can tie off things properly.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('simple port tie off to 0', () {
    final mod = BridgeModule('mod')
      ..addInput('apple', null)
      ..addOutput('banana');

    mod.port('apple').tieOff();
    mod.port('banana').tieOff();

    expect(mod.input('apple').value.toInt(), 0);
    expect(mod.output('banana').value.toInt(), 0);
  });

  test('tie off a subset of a port', () {
    final mod = BridgeModule('mod')
      ..addInputArray('apple', null, dimensions: [4], elementWidth: 4)
      ..addOutputArray('banana', dimensions: [4], elementWidth: 4);

    mod.port('apple[1][2:1]').tieOff();
    mod.port('banana[1][2:1]').tieOff();

    expect(mod.input('apple').value,
        LogicValue.of('${'z' * 4}${'z' * 4}z00z${'z' * 4}'));
    expect(mod.output('banana').value,
        LogicValue.of('${'z' * 4}${'z' * 4}z00z${'z' * 4}'));
  });

  test('tie off with non-zero value', () {
    final mod = BridgeModule('mod')
      ..addInput('apple', null, width: 4)
      ..addOutput('banana', width: 4);

    mod.port('apple').tieOff(value: '01xz');
    mod.port('banana').tieOff(value: '01xz');

    expect(mod.input('apple').value, LogicValue.of('01xz'));
    expect(mod.output('banana').value, LogicValue.of('01xz'));
  });

  test('tieOff an output and verify RTL', () async {
    final mod = BridgeModule('mod')..addOutput('banana', width: 4);

    mod.port('banana').tieOff(value: '10xz');

    final top = BridgeModule('top')
      ..addSubModule(mod)
      ..pullUpPort(mod.port('banana'));

    await top.build();
    final sv = mod.generateSynth();
    expect(sv, contains("assign banana = 4'b10xz;"));

    expect(mod.output('banana').value, LogicValue.of('10xz'));
  });

  test('zero tieOffs do not introduce named constants in RTL', () async {
    final mod = BridgeModule('mod')..addOutput('banana', width: 8);

    for (var i = 0; i < mod.output('banana').width; i++) {
      mod.port('banana[$i]').tieOff();
    }

    await mod.build();
    final sv = mod.generateSynth();

    expect(sv, isNot(contains('tieoff_const0')));
    expect(mod.output('banana').value, LogicValue.filled(8, LogicValue.zero));
  });

  test('non-zero tieOffs preserve a shared readable constant in RTL', () async {
    final mod = BridgeModule('mod')
      ..addOutput('apple', width: 8)
      ..addOutput('banana', width: 8);

    mod.port('apple[7:0]').tieOff(value: 0x5a);
    mod.port('banana[7:0]').tieOff(value: 0x5a);

    await mod.build();
    final sv = mod.generateSynth();

    expect(RegExp("8'h5a").allMatches(sv), hasLength(2));
    expect(sv, isNot(contains('tieoff_const90')));
    expect(sv, isNot(contains('tieoff_const90_0')));
    expect(mod.output('apple').value, LogicValue.ofInt(0x5a, 8));
    expect(mod.output('banana').value, LogicValue.ofInt(0x5a, 8));
  });

  test('tieOff with fill', () {
    final mod = BridgeModule('mod')
      ..addInput('apple', null, width: 8)
      ..addOutput('banana', width: 8);

    mod.port('apple').tieOff(value: 1, fill: true);
    mod.port('banana').tieOff(value: 1, fill: true);

    expect(mod.input('apple').value, LogicValue.filled(8, LogicValue.one));
    expect(mod.output('banana').value, LogicValue.filled(8, LogicValue.one));
  });

  test('tieOffInterface ties off inputs based on role', () {
    final intf = PairInterface(
      portsFromProvider: [Logic.port('fromProv', 4)],
      portsFromConsumer: [Logic.port('fromCons', 4)],
    );

    final mod = BridgeModule('mod')
      ..addInterface(intf, name: 'myIntf', role: PairRole.consumer);

    mod.tieOffInterface(mod.interface('myIntf'), value: 5);

    // Consumer receives from provider, so fromProv should be tied off
    expect(mod.interface('myIntf').port('fromProv').portSubsetLogic.value,
        LogicValue.of('0101'));
    // fromCons is an output from consumer's perspective, not tied off
    expect(mod.interface('myIntf').port('fromCons').portSubsetLogic.value,
        LogicValue.filled(4, LogicValue.z));
  });

  test('tieOffInterface with fill', () {
    final intf = PairInterface(
      portsFromProvider: [Logic.port('fromProv', 8)],
    );

    final mod = BridgeModule('mod')
      ..addInterface(intf, name: 'myIntf', role: PairRole.consumer);

    mod.tieOffInterface(mod.interface('myIntf'), value: 1, fill: true);

    expect(mod.interface('myIntf').port('fromProv').portSubsetLogic.value,
        LogicValue.filled(8, LogicValue.one));
  });

  test('tieOffInterface defaults to 0', () {
    final intf = PairInterface(
      portsFromProvider: [Logic.port('fromProv', 8)],
    );

    final mod = BridgeModule('mod')
      ..addInterface(intf, name: 'myIntf', role: PairRole.consumer);

    mod.tieOffInterface(mod.interface('myIntf'));

    expect(mod.interface('myIntf').port('fromProv').portSubsetLogic.value,
        LogicValue.filled(8, LogicValue.zero));
  });
}
