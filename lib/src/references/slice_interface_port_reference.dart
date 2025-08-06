// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// slice_interface_port_reference.dart
// Definitions for accessing interface ports with slices.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

part of 'references.dart';

/// A reference to a sliced portion of an interface port.
///
/// This class combines the functionality of [SlicePortReference] with
/// [InterfacePortReference] to provide access to specific bits or array
/// elements within an interface port.
class SliceInterfacePortReference extends SlicePortReference
    with InterfacePortReference {
  @override
  final InterfaceReference interfaceReference;

  /// Creates a reference to a sliced interface port.
  ///
  /// The slice is defined by [dimensionAccess] for indexing and
  /// [sliceUpperIndex]/[sliceLowerIndex] for slicing.
  SliceInterfacePortReference(
    super.module,
    super.portName, {
    required this.interfaceReference,
    super.dimensionAccess,
    super.sliceUpperIndex,
    super.sliceLowerIndex,
  });

  /// Creates a slice reference from a port access string.
  ///
  /// Parses the [portAccessString] to extract slicing and indexing information,
  /// then creates the appropriate slice reference. The string can include array
  /// indexing and slicing syntax.
  factory SliceInterfacePortReference.fromString(
    InterfaceReference interfaceReference,
    String portAccessString,
  ) {
    final components =
        SlicePortReference.extractPortAccessSliceComponents(portAccessString);

    return SliceInterfacePortReference(
      interfaceReference.module,
      components.portName,
      interfaceReference: interfaceReference,
      dimensionAccess: components.dimensionAccess,
      sliceUpperIndex: components.sliceUpperIndex,
      sliceLowerIndex: components.sliceLowerIndex,
    );
  }

  @override
  SliceInterfacePortReference slice(int endIndex, int startIndex) {
    final (newLowerIndex, newUpperIndex) =
        getUpdatedSliceIndices(endIndex, startIndex);

    return SliceInterfacePortReference(
      module,
      portName,
      dimensionAccess: dimensionAccess,
      sliceLowerIndex: newLowerIndex,
      sliceUpperIndex: newUpperIndex,
      interfaceReference: interfaceReference,
    );
  }
}
