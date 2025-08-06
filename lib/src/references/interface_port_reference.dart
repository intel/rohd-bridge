// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interface_port_reference.dart
// Definitions for a port reference that is part of an interface.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

part of 'references.dart';

/// A mixin that provides interface-specific behavior for port references.
///
/// This mixin extends [PortReference] with functionality specific to ports that
/// belong to interfaces. It handles direction resolution based on the interface
/// role and port direction tags, and provides access to the appropriate
/// internal or external port based on the connection context.
mixin InterfacePortReference on PortReference {
  /// The interface that contains this port.
  InterfaceReference get interfaceReference;

  /// Whether this port is tagged as [PairDirection.fromProvider].
  late final _isFromProvider =
      interfaceReference._interfaceFromProviderPorts[portName] != null;

  /// Whether this port is tagged as [PairDirection.fromConsumer].
  late final _isFromConsumer =
      interfaceReference._interfaceFromConsumerPorts[portName] != null;

  /// Whether this port is tagged as [PairDirection.commonInOuts].
  late final _isFromCommonInOut =
      interfaceReference._interfaceFromCommonInOutPorts[portName] != null;

  /// Whether this port is tagged as [PairDirection.sharedInputs].
  late final _isSharedInput =
      interfaceReference._interfaceSharedInputPorts[portName] != null;

  /// The effective direction of this port based on interface role and port
  /// tags.
  ///
  /// This resolves the actual port direction by considering:
  /// - The interface role (provider or consumer)
  /// - The port's direction tags (fromProvider, fromConsumer, etc.)
  ///
  /// For example, a port tagged as [PairDirection.fromProvider] will be an
  /// output when the interface role is [PairRole.provider], but an input when
  /// the role is [PairRole.consumer].
  @override
  PortDirection get direction {
    if (_isSharedInput) {
      return PortDirection.input;
    }

    if (_isFromCommonInOut) {
      return PortDirection.inOut;
    }

    if (interfaceReference.role == PairRole.provider) {
      if (_isFromProvider) {
        return PortDirection.output;
      } else if (_isFromConsumer) {
        return PortDirection.input;
      }
    } else if (interfaceReference.role == PairRole.consumer) {
      if (_isFromProvider) {
        return PortDirection.input;
      } else if (_isFromConsumer) {
        return PortDirection.output;
      }
    }

    throw RohdBridgeException('Port $this is directionless.');
  }

  /// Whether this port has no directional tags.
  ///
  /// Returns `true` if the port is not tagged with any of the [PairDirection]
  /// values. Such ports are considered directionless.
  bool get isDirectionless =>
      !_isSharedInput &&
      !_isFromCommonInOut &&
      !_isFromProvider &&
      !_isFromConsumer;

  /// The appropriate logic port for this interface port reference.
  ///
  /// Returns either the `internal interface` port or the external interface
  /// port, depending on the resolved direction and whether an internal
  /// interface exists.
  @override
  Logic get port => (!isDirectionless &&
              (direction == PortDirection.input ||
                  direction == PortDirection.inOut)
          ? (interfaceReference.internalInterface ??
              interfaceReference.interface)
          : interfaceReference.interface)
      .port(portName);

  @override
  // TODO(mkorbel1): remove lint waiver pending https://github.com/dart-lang/sdk/issues/56532
  // ignore: unused_element
  Logic get _receiver => !isDirectionless &&
          (direction == PortDirection.input || direction == PortDirection.inOut)
      ? interfaceReference.interface.port(portName)
      : (interfaceReference.internalInterface ?? interfaceReference.interface)
          .port(portName);

  @override
  String toString() => '$interfaceReference.${super.toString()}';
}
