// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// submodule_find_test.dart
// Unit tests for finding submodules in the hierarchy.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('submodule search', () {
    final topMod = BridgeModule('topMod')
      ..addSubModule(
        BridgeModule('myUpperMid')
          ..addSubModule(
            BridgeModule('myLowerMid')
              ..addSubModule(
                BridgeModule('myLeaf'),
              )
              ..addSubModule(
                BridgeModule('myLeaf2'),
              ),
          )
          ..addSubModule(
            BridgeModule('myLowerMid2')
              ..addSubModule(
                BridgeModule('myLeaf'),
              )
              ..addSubModule(
                BridgeModule('myLeaf2'),
              ),
          ),
      );

    test('find all myLeafs', () {
      final leafs = topMod.findSubModules('myLeaf');
      expect(leafs.length, 2);
    });

    test('find top', () {
      final top = topMod.findSubModule('topMod');
      expect(top, topMod);
    });

    test('find myLeaf under lower-mid 1', () {
      final leafs = topMod.findSubModules('myLowerMid/myLeaf');
      expect(leafs.length, 1);
    });

    test('find one myLeaf throws exception', () {
      expect(() => topMod.findSubModule('myLeaf'), throwsException);
    });

    test('find non-existant module returns null', () {
      final leaf = topMod.findSubModule('myLowerMid/myLeaf3');
      expect(leaf, null);
    });

    test('find one myLeaf under myLowerMid, and hierarchy right', () {
      final leaf = topMod.findSubModule('myLowerMid/myLeaf');
      expect(leaf, isNotNull);
      expect(leaf!.name, 'myLeaf');

      final hier = leaf.hierarchy();
      final hierStr = hier.map((e) => e.name).join('/');
      expect(hierStr, 'topMod/myUpperMid/myLowerMid/myLeaf');
    });

    test('find non-existant module returns empty list', () {
      final leafs = topMod.findSubModules('myLowerMid/myLeaf3');
      expect(leafs.length, 0);
    });

    test('find modules with myLeaf in name', () {
      final leafs = topMod.findSubModules(RegExp('myLeaf'));
      expect(leafs.length, 4);
    });

    test('find modules underneath myLowerMid2', () {
      final leafs = topMod.findSubModules(RegExp('myLowerMid2/'));
      expect(leafs.length, 2);
    });

    test('find all modules in myLowerMid2, including myLowerMid2', () {
      final allMods = topMod.findSubModules(RegExp('myLowerMid2'));
      expect(allMods.length, 3);
    });
  });

  test('duplicate leaf finds both', () {
    final topMod = BridgeModule('top')
      ..addSubModule(BridgeModule('leaf'))
      ..addSubModule(BridgeModule('leaf'));

    expect(topMod.findSubModules('leaf').length, 2);
  });
}
