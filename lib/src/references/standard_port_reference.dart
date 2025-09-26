// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// standard_port_reference.dart
// Definitions for accessing ports with no special slicing.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

part of 'references.dart';

/// A [PortReference] that refers to a complete, unsliced port.
///
/// This represents a reference to an entire port on a [BridgeModule] without
/// any bit-level slicing or array indexing. It provides direct access to the
/// full width of the port.
@immutable
class StandardPortReference extends PortReference {
  /// Creates a [StandardPortReference] for the specified port.
  ///
  /// The [portName] must be a simple identifier without any slicing or indexing
  /// syntax (e.g., "myPort", not "myPort[3:0]").
  StandardPortReference(super.module, super.portName) : super._() {
    if (!_isStandardAccess(portName)) {
      throw RohdBridgeException('Invalid standard access: $portName');
    }
  }

  /// Regular expression pattern for valid standard port names.
  ///
  /// Matches simple identifiers consisting of letters, numbers, and
  /// underscores, without any slicing or indexing syntax.
  static final RegExp _standardPortAccessRegex = RegExp(r'^[a-zA-Z0-9_]+$');

  /// Checks if a port access string represents a standard (unsliced) port.
  ///
  /// Returns `true` if [portAccessString] is a simple port name without any
  /// bracket notation for slicing or indexing.
  static bool _isStandardAccess(String portAccessString) =>
      _standardPortAccessRegex.hasMatch(portAccessString);

  @override
  void gets(PortReference other) {
    if (other is StandardPortReference) {
      final (receiver: receiver, driver: driver) =
          _relativeReceiverAndDriver(other);
      receiver <= driver;
    } else if (other is SlicePortReference) {
      final otherDriver = _relativeDriverSubset(other);
      final receiver = _relativeReceiverAndDriver(other).receiver;

      if (otherDriver is Logic) {
        receiver <= otherDriver;
      } else if (otherDriver is List<Logic>) {
        if (receiver is LogicArray &&
            receiver.dimensions.first == otherDriver.length) {
          receiver.assignSubset(otherDriver);
        } else {
          receiver <= otherDriver.rswizzle();
        }
      } else {
        throw RohdBridgeException('Invalid driver type $otherDriver');
      }
    } else {
      throw RohdBridgeException('Invalid driver type $other');
    }
  }

  @override
  late final Logic portSubset = port;

  @override
  dynamic get _externalPortSubset => _externalPort;

  @override
  Logic get _internalPortSubset => _internalPort;

  @override
  PortReference replicateTo(BridgeModule newModule, PortDirection direction,
      {String? newPortName}) {
    newPortName ??= portName;
    if (port is LogicArray) {
      final portArr = port as LogicArray;
      newModule.createArrayPort(newPortName, direction,
          dimensions: portArr.dimensions, elementWidth: portArr.elementWidth);
    } else {
      newModule.createPort(newPortName, direction, width: port.width);
    }

    return PortReference.fromString(newModule, newPortName);
  }

  @override
  void drivesLogic(Logic other) {
    other <= portSubset;
  }

  @override
  void getsLogic(Logic other) {
    _externalPort <= other;
  }

  @override
  PortReference slice(int endIndex, int startIndex) =>
      startIndex == 0 && endIndex == width - 1
          ? this
          : SlicePortReference(
              module,
              portName,
              sliceLowerIndex: startIndex,
              sliceUpperIndex: endIndex,
            );
}
