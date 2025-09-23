// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bridge_interface.dart
// Definition for custom `PairInterface`.
//
// 2024 August 6
// Authors:
//    Shankar Sharma <shankar.sharma@intel.com>
//    Suhas Virmani <suhas.virmani@intel.com>
//    Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

/// A custom interface created dynamically from a provided specification.
class BridgeInterface extends PairInterface {
  /// name of intf
  late String name;

  /// vendor of intf
  late String vendor;

  /// library of intf
  late String library;

  /// version of intf
  late String version;

  /// Internal copy of `portsFromConsumer` map.
  final Map<String, int> _portsFromConsumer;

  /// Internal copy of `portsFromProvider` map.
  final Map<String, int> _portsFromProvider;

  /// Internal copy of `portsSharedInouts` map.
  final Map<String, int> _portsSharedInouts;

  /// Reads [portsFromConsumer], [portsFromProvider] and [portsSharedInouts]
  /// then creates appropriate ports with appropriate tags.
  BridgeInterface({
    required this.name,
    required this.library,
    required this.vendor,
    required this.version,
    Map<String, int> portsFromConsumer = const {},
    Map<String, int> portsFromProvider = const {},
    Map<String, int> portsSharedInouts = const {},
  })  : _portsFromConsumer = portsFromConsumer,
        _portsFromProvider = portsFromProvider,
        _portsSharedInouts = portsSharedInouts {
    for (final port in portsFromConsumer.entries) {
      if (tryPort(port.key) == null) {
        setPorts(
            [Logic.port(port.key, port.value)], [PairDirection.fromConsumer]);
      }
    }

    for (final port in portsFromProvider.entries) {
      if (tryPort(port.key) == null) {
        setPorts(
            [Logic.port(port.key, port.value)], [PairDirection.fromProvider]);
      }
    }

    for (final port in portsSharedInouts.entries) {
      if (tryPort(port.key) == null) {
        setPorts(
            [Logic.port(port.key, port.value)], [PairDirection.commonInOuts]);
      }
    }
  }

  /// Creates a custom [BridgeInterface] from [json].
  @Deprecated('Use `BridgeInterface` unnamed constructor instead.')
  factory BridgeInterface.ofJson(Map<String, dynamic> json) {
    final portsFromConsumer =
        json['portsOnConsumer'] as Map<String, int>? ?? {};
    final portsFromProvider =
        json['portsOnProvider'] as Map<String, int>? ?? {};
    final portsSharedInouts =
        json['portsSharedInouts'] as Map<String, int>? ?? {};

    return BridgeInterface(
        name: json['name'] as String,
        vendor: json['vendor'] as String,
        library: json['library'] as String,
        version: json['version'] as String,
        portsFromConsumer: portsFromConsumer,
        portsFromProvider: portsFromProvider,
        portsSharedInouts: portsSharedInouts);
  }

  @override
  BridgeInterface clone() => BridgeInterface(
      name: name,
      library: library,
      vendor: vendor,
      version: version,
      portsFromConsumer: _portsFromConsumer,
      portsFromProvider: _portsFromProvider,
      portsSharedInouts: _portsSharedInouts);
}
