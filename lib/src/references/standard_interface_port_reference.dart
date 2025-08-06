// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// standard_interface_port_reference.dart
// Definitions for accessing simple interface ports.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

part of 'references.dart';

/// A reference to a complete, unsliced port within an interface.
///
/// This class combines the functionality of [StandardPortReference] with
/// [InterfacePortReference] to provide access to entire interface ports without
/// any bit-level slicing or array indexing.
class StandardInterfacePortReference extends StandardPortReference
    with InterfacePortReference {
  @override
  final InterfaceReference interfaceReference;

  /// Creates a reference to a complete interface port.
  ///
  /// The [portName] must exist within the [interfaceReference]'s interface and
  /// must be a simple identifier without slicing syntax.
  StandardInterfacePortReference(this.interfaceReference, String portName)
      : super(interfaceReference.module, portName);

  @override
  InterfacePortReference slice(int endIndex, int startIndex) =>
      startIndex == 0 && endIndex == width - 1
          ? this
          : SliceInterfacePortReference(
              module,
              portName,
              sliceLowerIndex: startIndex,
              sliceUpperIndex: endIndex,
              interfaceReference: interfaceReference,
            );
}
