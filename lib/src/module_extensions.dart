// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// module_extensions.dart
// Additional functionality on `Module`s to facilitate searching and hierarchy
// management.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

/// Extension methods for [Module] to provide additional functionality related
/// to ROHD Bridge.
extension RohdBridgeModuleExtensions on Module {
  /// Searches for sub-modules by instance name [pattern] within this [Module].
  /// The [String] representation being matched against uses `/` as a separator
  /// for hierarchy.
  ///
  /// If a [String] is provided, it will search for an exact match to the end of
  /// a hierarchy.  If a [RegExp] is provided, it will search for a match
  /// anywhere in the hierarchy.
  ///
  /// Some examples:
  ///
  /// ```dart
  /// // Real hierarchy:
  /// // myTop/myUpperMid/myLowerMid/myLeaf
  ///
  /// // Find all modules with the name "myLeaf"
  /// findSubModules('myLeaf');
  ///
  /// // Find all modules with the name "myLowerMid"
  /// findSubModules('myLowerMid');
  ///
  /// // Find modules named "myLeaf" directly within "myLowerMid"
  /// findSubModules('myLowerMid/myLeaf');
  ///
  /// // Find modules named "myLowerMid" directly within "myUpperMid"
  /// findSubModules('myUpperMid/myLowerMid');
  ///
  /// // Find all modules underneath "myUpperMid"
  /// findSubModules(RegExp('myUpperMid/.*')); // finds myLowerMid and myLeaf
  ///
  /// // Find all modules underneath "myUpperMid" named "myLeaf"
  /// findSubModules(RegExp('myUpperMid/.*/?myLeaf$'));
  /// ```
  ///
  /// The returned [Iterable] is lazy, so it will only search through the
  /// hierarchy as long as it is iterated against.
  Iterable<Module> findSubModules(Pattern pattern) => _findSubModules(pattern);

  Iterable<Module> _findSubModules(Pattern pattern,
      [String? hierarchyAbove]) sync* {
    final currHier = hierarchyAbove == null ? name : '$hierarchyAbove/$name';

    if (pattern is String) {
      if (currHier.endsWith('/$pattern') || currHier == pattern) {
        yield this;
      }
    } else if (pattern is RegExp) {
      if (pattern.hasMatch(currHier)) {
        yield this;
      }
    } else {
      throw RohdBridgeException('Invalid pattern type: $pattern');
    }

    for (final mod in subModules) {
      yield* mod._findSubModules(pattern, currHier);
    }
  }

  /// Searches for one sub-module matching [pattern] in the same way as
  /// [findSubModules]. If more than one module is found, an exception is
  /// thrown.
  Module? findSubModule(Pattern pattern) {
    final foundSubMods = findSubModules(pattern);
    final iter = foundSubMods.iterator;

    final firstFound = iter.moveNext() ? iter.current : null;
    final secondFound = iter.moveNext() ? iter.current : null;

    if (secondFound != null) {
      throw RohdBridgeException('More than one module found matching $pattern:'
          ' $firstFound and $secondFound');
    } else {
      return firstFound;
    }
  }

  /// Provides a full hierarchical name based on [hierarchy].
  String get hierarchicalName => hierarchy().map((e) => e.name).join('.');

  /// Returns a list of instances between calling module `this` and the provided
  /// [instance], where the first element is `this` and the last element is
  /// [instance].
  ///
  /// If there is no path found, returns `null`. If [instance] is the same as
  /// `this`, returns a list with just the one module in it.
  List<Module>? getHierarchyDownTo(Module instance) {
    if (instance == this) {
      return [this];
    }

    Module? parent = instance;

    final fullPath = <Module>[];

    while (parent != null) {
      fullPath.add(parent);

      if (parent == this) {
        break;
      }

      parent = parent.parent;
    }

    if (parent != this) {
      return null;
    }

    return fullPath.reversed.toList(growable: false);
  }
}

/// Returns the common parent of two modules [firstChild] and [secondChild]
/// Assuming at least one common parent exists
Module? findCommonParent(Module firstChild, Module secondChild) {
  final firstPath = List<Module>.from(firstChild.hierarchy(), growable: false);
  final secondPath =
      List<Module>.from(secondChild.hierarchy(), growable: false);

  if (firstChild.parent == secondChild.parent && firstChild.parent != null) {
    return firstChild.parent;
  }

  if (firstPath[0] != secondPath[0]) {
    // base top parent is not the same, no common parent
    return null;
  }

  if (secondPath.contains(firstChild) && !firstPath.contains(secondChild)) {
    // firstChild is in the parent hierarchy of second
    return firstChild;
  } else if (!secondPath.contains(firstChild) &&
      firstPath.contains(secondChild)) {
    // secondChild is in the parent hierarchy of first
    return secondChild;
  }

  for (var i = 0; i < firstPath.length; i++) {
    if (firstPath[i] != secondPath[i]) {
      // Assumption there has to be one common parent at the top
      return firstPath[i - 1];
    }
  }

  return null;
}
