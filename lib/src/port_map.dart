// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_map.dart
// Port map implementation between an interface port and a module port.
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>
//

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

/// Represents a mapping between a [PortReference] and an
/// [InterfacePortReference] on a particular [BridgeModule].
class PortMap {
  /// A port on the [Interface].
  final InterfacePortReference interfacePort;

  /// A port on the [Module].
  final PortReference port;

  /// Indicates that [port] and [interfacePort] are actually connected, not just
  /// mapped pending a connection.
  bool get isConnected => _isConnected;
  bool _isConnected = false;

  /// Creates a new [PortMap] instance.
  ///
  /// If [preConnected] is `true`, the port map is considered resolved and will
  /// not attempt to resolve the connection when [connect] is called.
  ///
  /// This should only be constructed by calling [BridgeModule.addPortMap] or
  /// [InterfaceReference.addPortMap].
  @internal
  PortMap(
      {required this.port,
      required this.interfacePort,
      bool preConnected = false}) {
    if (!interfacePort.isDirectionless &&
        port.direction != interfacePort.direction) {
      throw RohdBridgeException('Port direction mismatch: '
          '${port.direction} vs ${interfacePort.direction}');
    }

    if (port.module != interfacePort.interfaceReference.module) {
      throw RohdBridgeException(
          'Port and InterfacePort must be in the same module.');
    }

    if (!preConnected &&
        interfacePort.interfaceReference.internalInterface != null) {
      throw RohdBridgeException('Cannot connect a port to an interface which'
          ' already has an internal interface.');
    }

    if (port is InterfacePortReference) {
      throw RohdBridgeException(
          'Cannot connect a port to an InterfacePortReference '
          'as it is already an interface port.');
    }

    _isConnected = preConnected;
  }

  /// Resolves a port map by connecting the [port] to the [interfacePort] in
  /// the appropriate direction.
  ///
  /// Returns `true` if the port map was successfully connected, or `false` if
  /// it was already connected.
  bool connect() {
    if (_isConnected) {
      return false;
    }

    switch (port.direction) {
      case PortDirection.input || PortDirection.inOut:
        port.gets(interfacePort);
      case PortDirection.output:
        interfacePort.gets(port);
    }
    _isConnected = true;

    return true;
  }

  @override
  String toString() => '( $port <=> $interfacePort )';
}
