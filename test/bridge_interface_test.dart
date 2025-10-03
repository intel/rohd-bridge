// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bridge_interface_test.dart
// Unit tests for standard interface JSON parsing.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/src/bridge_interface.dart';
import 'package:test/test.dart';

void main() {
  test('Bridge Interface simple', () {
    final portsFromConsumer = {'a': 1, 'b': 2, 'c': 3};
    final portsFromProvider = {'d': 4, 'e': 5, 'f': 6};
    final intf = BridgeInterface(
        vendor: 'SomeVendor',
        library: 'SomeLibrary',
        name: 'my_intf',
        version: '1.0',
        portsFromConsumer: portsFromConsumer,
        portsFromProvider: portsFromProvider);

    expect(intf.vendor, 'SomeVendor');
    expect(intf.library, 'SomeLibrary');
    expect(intf.name, 'my_intf');
    expect(intf.version, '1.0');

    final portsOnConsumer = intf.getPorts([PairDirection.fromConsumer]);
    final portsOnProvider = intf.getPorts([PairDirection.fromProvider]);

    for (final port in portsFromConsumer.keys) {
      expect(portsOnConsumer.keys, contains(port));
      expect(portsOnConsumer[port]!.width, portsFromConsumer[port]);
    }
    for (final port in portsFromProvider.keys) {
      expect(portsOnProvider, contains(port));
      expect(portsOnProvider[port]!.width, portsFromProvider[port]);
    }
  });
}
