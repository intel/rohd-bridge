// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_bridge_exception.dart
// Base class for exceptions thrown by ROHD Bridge.
//
// 2025 August
// Authors:
//    Max Korbel <max.korbel@intel.com>

/// Base class for [Exception]s thrown by ROHD Bridge.
class RohdBridgeException implements Exception {
  /// A description of what this exception means.
  final String message;

  /// Creates a new exception with description [message].
  RohdBridgeException(this.message);

  @override
  String toString() => message;
}
