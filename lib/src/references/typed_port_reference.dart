// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// typed_port_reference.dart
// Definitions for typed access to port references.
//
// 2026 August 12
// Author: Max Korbel <max.korbel@intel.com>

part of 'references.dart';

/// A typed view of a [PortReference].
///
/// [PortType] is the concrete type of the root [port]. It does not describe
/// [portSubset], whose type can change based on slicing and array indexing.
///
/// This extension type implements [PortReference], so it can be passed directly
/// to existing APIs that accept an untyped reference without allocation or
/// conversion.
extension type TypedPortReference<PortType extends Logic>._(
    PortReference _reference) implements PortReference {
  /// Creates a typed view of [reference].
  ///
  /// Throws a [RohdBridgeException] if the referenced port is not a [PortType].
  factory TypedPortReference(PortReference reference) {
    if (reference.port is! PortType) {
      throw RohdBridgeException('Port $reference on ${reference.module} is a '
          '${reference.port.runtimeType}, not a $PortType.');
    }

    return TypedPortReference<PortType>._(reference);
  }

  /// The root port with its checked concrete type.
  @redeclare
  PortType get port => _reference.port as PortType;
}

/// Checked typed views for [PortReference]s.
extension TypedPortReferenceConversions on PortReference {
  /// Returns this reference as a [TypedPortReference] when its root port is a
  /// [PortType].
  ///
  /// Throws a [RohdBridgeException] if the referenced port is not a [PortType].
  TypedPortReference<PortType> asTyped<PortType extends Logic>() =>
      TypedPortReference<PortType>(this);

  /// Returns this reference as a [TypedPortReference], or `null` if its root
  /// port is not a [PortType].
  TypedPortReference<PortType>? tryAsTyped<PortType extends Logic>() =>
      port is PortType ? TypedPortReference<PortType>._(this) : null;
}
