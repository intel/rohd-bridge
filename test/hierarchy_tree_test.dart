// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_tree_test.dart
// Unit tests for pretty-printing module hierarchy.
//
// 2026 September 12
// Author: KayanoLiam <Kayano04@outlook.jp>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class _HierarchyTreeModule extends BridgeModule {
  _HierarchyTreeModule() : super('top');

  @override
  String hierarchyTree() => 'Bridge hierarchy:\n${super.hierarchyTree()}';
}

void main() {
  test('hierarchy tree can be overridden in BridgeModule subclasses', () {
    final top = _HierarchyTreeModule()..addSubModule(BridgeModule('leaf'));

    expect(top.hierarchyTree(), 'Bridge hierarchy:\ntop\n└── leaf');
  });

  test('single module has only its name', () {
    expect(BridgeModule('leaf').hierarchyTree(), 'leaf');
  });

  test('tree uses box-drawing branches', () {
    final top = BridgeModule('top')
      ..addSubModule(
        BridgeModule('east')..addSubModule(BridgeModule('leaf')),
      )
      ..addSubModule(BridgeModule('west'));

    expect(
      top.hierarchyTree(),
      'top\n'
      '├── east\n'
      '│   └── leaf\n'
      '└── west',
    );
  });

  test('tree can start from a module below the top', () {
    final topMod = BridgeModule('topMod')
      ..addSubModule(
        BridgeModule('myUpperMid')
          ..addSubModule(
            BridgeModule('myLowerMid')
              ..addSubModule(BridgeModule('myLeaf'))
              ..addSubModule(BridgeModule('myLeaf2')),
          )
          ..addSubModule(
            BridgeModule('myLowerMid2')
              ..addSubModule(BridgeModule('myLeaf'))
              ..addSubModule(BridgeModule('myLeaf2')),
          ),
      );

    expect(
      (topMod.findSubModule('myUpperMid')! as BridgeModule).hierarchyTree(),
      'myUpperMid\n'
      '├── myLowerMid\n'
      '│   ├── myLeaf\n'
      '│   └── myLeaf2\n'
      '└── myLowerMid2\n'
      '    ├── myLeaf\n'
      '    └── myLeaf2',
    );
  });

  test('definition name is shown when it differs from instance name', () {
    final top = BridgeModule('soc', name: 'u_soc')
      ..addSubModule(BridgeModule('cpu', name: 'u_cpu'));

    expect(
      top.hierarchyTree(),
      'u_soc (soc)\n'
      '└── u_cpu (cpu)',
    );
  });

  for (final nested in [false, true]) {
    test('built bridge leaf excludes internal logic (nested: $nested)',
        () async {
      final leaf = BridgeModule('leaf');
      final a = leaf.addInput('a', Logic());
      leaf.addOutput('y') <= ~a;

      final root = nested ? BridgeModule('top') : leaf;
      if (nested) {
        root
          ..addSubModule(leaf)
          ..addInput('a', null)
          ..addOutput('y');
        connectPorts(root.port('a'), leaf.port('a'));
        connectPorts(leaf.port('y'), root.port('y'));
      }

      final expected = nested ? 'top\n└── leaf' : 'leaf';
      expect(root.hierarchyTree(), expected);

      await root.build();

      expect(leaf.subModules, isNotEmpty);
      expect(leaf.subBridgeModules, isEmpty);
      expect(leaf.hierarchyTree(), 'leaf');
      expect(root.hierarchyTree(), expected);
    });
  }

  test('constructed tree is unchanged after build', () async {
    final top = BridgeModule('top');
    final east = top.addSubModule(BridgeModule('east'));
    final west = top.addSubModule(BridgeModule('west'));

    top.addInput('clk', null);
    east.addInput('clk', null);
    connectPorts(top.port('clk'), east.port('clk'));

    east.addOutput('myOutput', width: 4);
    west.addInput('myInput', null, width: 4);
    connectPorts(east.port('myOutput'), west.port('myInput'));

    const expected = 'top\n'
        '├── east\n'
        '└── west';

    expect(top.hierarchyTree(), expected);

    await top.build();

    expect(top.hierarchyTree(), expected);
  });
}
