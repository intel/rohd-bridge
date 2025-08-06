// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// intf_port_access_test.dart
// Unit tests for port accesses on interfaces.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class AccessIntf extends PairInterface {
  AccessIntf()
      : super(
          portsFromProvider: [
            Logic.port('smallPortFromProvider', 4),
            LogicArray.port('arrPortFromProvider', [8]),
          ],
          portsFromConsumer: [
            Logic.port('portFromConsumer', 8),
            LogicArray.port('smallArrPortFromConsumer', [4]),
          ],
        );

  @override
  AccessIntf clone() => AccessIntf();
}

class IntfPortAccessModule extends BridgeModule {
  IntfPortAccessModule([PairRole role = PairRole.provider])
      : super('intfPortAccessModule') {
    addInterface(AccessIntf(), name: 'accessIntf', role: role);
    addInput('myInput', null, width: 4);
    addOutput('myOutput', width: 4);
    addInput('myInputWide', null, width: 8);
    addOutput('myOutputWide', width: 8);
  }
}

class BadMappingModule extends BridgeModule {
  BadMappingModule() : super('badMappingModule') {
    addInterface(AccessIntf(), name: 'accessIntf', role: PairRole.consumer);
    addInput('myInput', null, width: 4);
    addPortMap(
        port('myInput'), interface('accessIntf').port('smallPortFromProvider'));
  }
}

@immutable
class AccessExample {
  final String name;
  final PortReference Function(BridgeModule mod) portGetter;
  const AccessExample(this.name, this.portGetter);

  @override
  String toString() => name;
}

void main() {
  group('intf driver/receiver pairs', () {
    final receivers = [
      AccessExample('std input', (mod) => mod.port('myInput')),
      AccessExample(
          'intf std input',
          (mod) =>
              mod.interface('accessIntf').port('smallArrPortFromConsumer')),
      AccessExample('slice input', (mod) => mod.port('myInputWide[3:0]')),
      AccessExample('intf slice input',
          (mod) => mod.interface('accessIntf').port('portFromConsumer[3:0]')),
    ];

    final drivers = [
      AccessExample('std output', (mod) => mod.port('myOutput')),
      AccessExample('intf std output',
          (mod) => mod.interface('accessIntf').port('smallPortFromProvider')),
      AccessExample('slice output', (mod) => mod.port('myOutputWide[3:0]')),
      AccessExample(
          'intf slice output',
          (mod) =>
              mod.interface('accessIntf').port('arrPortFromProvider[3:0]')),
    ];

    for (final receiverEx in receivers) {
      for (final driverEx in drivers) {
        test('$driverEx -> $receiverEx', () {
          final mod = IntfPortAccessModule();

          final receiver = receiverEx.portGetter(mod);
          final driver = driverEx.portGetter(mod);

          receiver.gets(driver);
          driver.port.put(5);

          expect(receiver.port.value.getRange(0, 4).toInt(), 5);
        });
      }
    }
  });

  test('proper connection of slices between modules', () async {
    final sub1 = IntfPortAccessModule();
    final sub2 = IntfPortAccessModule();
    final top = BridgeModule('top')
      ..addSubModule(sub1)
      ..addSubModule(sub2);

    connectPorts(top.pullUpPort(sub1.port('myInput'), newPortName: 'myInput'),
        sub2.port('myInput'));
    connectPorts(
      sub1.interface('accessIntf').port('arrPortFromProvider[5:2]'),
      sub2.interface('accessIntf').port('portFromConsumer[6:3]'),
    );

    sub1
        .interface('accessIntf')
        .port('arrPortFromProvider')
        .port
        .put('xx1010xx');

    expect(
        sub2
            .interface('accessIntf')
            .port('portFromConsumer')
            .port
            .value
            .getRange(3, 7)
            .toInt(),
        10);

    await top.build();
  });

  test('port connection to interface with internal interface throws', () {
    expect(BadMappingModule.new, throwsException);
  });

  group('slice function', () {
    test('intf normal to slice', () {
      final mod = IntfPortAccessModule();
      expect(
        mod.interface('accessIntf').port('portFromConsumer').slice(3, 2),
        mod.interface('accessIntf').port('portFromConsumer[3:2]'),
      );
    });

    test('slice to smaller slice', () {
      final mod = IntfPortAccessModule();
      expect(
        mod.interface('accessIntf').port('portFromConsumer[6:2]').slice(2, 1),
        mod.interface('accessIntf').port('portFromConsumer[4:3]'),
      );
    });
  });
}
