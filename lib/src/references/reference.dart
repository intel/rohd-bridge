// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// reference.dart
// A generic reference to something on module boundary.
//
// 2025 June
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';

/// A generic reference to an element on a [BridgeModule] boundary.
///
/// This serves as the base class for all references to ports, interfaces, and
/// other elements that exist on the boundary of a [BridgeModule]. It provides a
/// common interface for accessing and manipulating these elements.
class Reference {
  // TODO(mkorbel1): can this be normal `Module`?
  /// The [BridgeModule] that this reference belongs to.
  final BridgeModule module;

  /// Creates a new [Reference] for the given [module].
  const Reference(this.module);
}
