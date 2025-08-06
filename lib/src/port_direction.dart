// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_direction.dart
// Definitions for port directions.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

/// A direction type for a port of a [Module].
enum PortDirection {
  /// Input.
  input,

  /// Output.
  output,

  /// In/Out.
  inOut;

  /// Converts from a name of [values] to a [PortDirection].
  static PortDirection fromString(String name) => values.firstWhere(
      (e) => e.name.toLowerCase() == name.toLowerCase(),
      orElse: () => throw RohdBridgeException('Invalid PortDirection: $name'));

  /// Identifies a [Module]'s port into a [PortDirection].
  static PortDirection ofPort(Logic port) {
    if (!port.isPort) {
      throw RohdBridgeException('$port is not a port.');
    }
    return port.isInput
        ? input
        : port.isOutput
            ? output
            : port.isInOut
                ? inOut
                : throw RohdBridgeException('Invalid PortDirection');
  }
}
