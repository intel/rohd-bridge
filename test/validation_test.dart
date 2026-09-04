// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// validation_test.dart
// Tests for validating references and port maps.
//
// 2026 September 4
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('reference validation', () {
    test('supports deferred port creation', () {
      final module = BridgeModule('dut');
      final reference = StandardPortReference(module, 'deferred');

      expect(reference.validate, throwsA(isA<RohdBridgeException>()));

      module.createPort('deferred', PortDirection.input);

      expect(reference.validate, returnsNormally);
    });

    test('validates the selected port subset', () {
      final module = BridgeModule('dut')
        ..createPort('data', PortDirection.input, width: 4);
      final validReference = SlicePortReference(
        module,
        'data',
        sliceLowerIndex: 2,
        sliceUpperIndex: 3,
      );
      final outOfRangeReference = SlicePortReference(
        module,
        'data',
        sliceLowerIndex: 3,
        sliceUpperIndex: 4,
      );

      expect(validReference.validate, returnsNormally);
      expect(outOfRangeReference.validate, throwsA(isA<RangeError>()));
    });
  });

  group('port map validation', () {
    test('validates the physical port', () {
      final module = BridgeModule('dut');
      final interfaceReference = module.addInterface(
        PairInterface(),
        name: 'interface',
        role: PairRole.provider,
        connect: false,
      );
      final portMap = module.addPortMap(
        StandardPortReference(module, 'missingPhysical'),
        StandardInterfacePortReference(
          interfaceReference,
          'missingLogical',
        ),
      );

      expect(portMap.validate, throwsA(isA<RohdBridgeException>()));
      expect(
        interfaceReference.validate,
        throwsA(isA<RohdBridgeException>()),
      );
      expect(portMap.isConnected, isFalse);
    });

    test('validates the interface port', () {
      final module = BridgeModule('dut')
        ..createPort('physical', PortDirection.input);
      final interfaceReference = module.addInterface(
        PairInterface(),
        name: 'interface',
        role: PairRole.provider,
        connect: false,
      );
      final portMap = module.addPortMap(
        module.port('physical'),
        StandardInterfacePortReference(
          interfaceReference,
          'missingLogical',
        ),
      );

      expect(portMap.validate, throwsA(isA<PortDoesNotExistException>()));
      expect(portMap.isConnected, isFalse);
    });

    test('does not connect valid endpoints', () {
      final module = BridgeModule('dut')
        ..createPort('physical', PortDirection.input);
      final interfaceReference = module.addInterface(
        PairInterface(portsFromProvider: [Logic.port('logical')]),
        name: 'interface',
        role: PairRole.consumer,
        connect: false,
      );
      final portMap = module.addPortMap(
        module.port('physical'),
        interfaceReference.port('logical'),
      );

      expect(portMap.validate, returnsNormally);
      expect(interfaceReference.validate, returnsNormally);
      expect(portMap.isConnected, isFalse);
    });

    test('requires endpoints to have the same width', () {
      final module = BridgeModule('dut')
        ..createPort('physical', PortDirection.input, width: 2);
      final interfaceReference = module.addInterface(
        PairInterface(portsFromProvider: [Logic.port('logical', 4)]),
        name: 'interface',
        role: PairRole.consumer,
        connect: false,
      );
      final portMap = module.addPortMap(
        module.port('physical'),
        interfaceReference.port('logical'),
      );

      expect(portMap.validate, throwsA(isA<RohdBridgeException>()));
      expect(portMap.isConnected, isFalse);
    });

    test('compares selected subset widths', () {
      final module = BridgeModule('dut')
        ..createPort('physical', PortDirection.input, width: 8);
      final interfaceReference = module.addInterface(
        PairInterface(portsFromProvider: [Logic.port('logical', 4)]),
        name: 'interface',
        role: PairRole.consumer,
        connect: false,
      );
      final portMap = module.addPortMap(
        module.port('physical[5:2]'),
        interfaceReference.port('logical'),
      );

      expect(portMap.validate, returnsNormally);
      expect(portMap.isConnected, isFalse);
    });

    test('rejects a physical input receiver with a source', () {
      final module = BridgeModule('dut')
        ..createPort('physical', PortDirection.input);
      final interfaceReference = module.addInterface(
        PairInterface(portsFromProvider: [Logic.port('logical')]),
        name: 'interface',
        role: PairRole.consumer,
        connect: false,
      );
      final portMap = module.addPortMap(
        module.port('physical'),
        interfaceReference.port('logical'),
      );

      module.inputSource('physical') <= Logic();

      expect(portMap.validate, throwsA(isA<RohdBridgeException>()));
      expect(portMap.isConnected, isFalse);
    });

    test('rejects an interface output receiver with a source', () {
      final module = BridgeModule('dut')
        ..createPort('physical', PortDirection.output);
      final interfaceReference = module.addInterface(
        PairInterface(portsFromProvider: [Logic.port('logical')]),
        name: 'interface',
        role: PairRole.provider,
        connect: false,
      );
      final portMap = module.addPortMap(
        module.port('physical'),
        interfaceReference.port('logical'),
      );

      interfaceReference.interface.port('logical') <= Logic();

      expect(portMap.validate, throwsA(isA<RohdBridgeException>()));
      expect(portMap.isConnected, isFalse);
    });

    test('allows source connections for inout maps', () {
      final module = BridgeModule('dut')
        ..createPort('physical', PortDirection.inOut);
      final interfaceReference = module.addInterface(
        PairInterface(commonInOutPorts: [LogicNet.port('logical')]),
        name: 'interface',
        role: PairRole.provider,
        connect: false,
      );
      final portMap = module.addPortMap(
        module.port('physical'),
        interfaceReference.port('logical'),
      );

      module.inOutSource('physical') <= LogicNet();

      expect(module.inOutSource('physical').srcConnections, isNotEmpty);
      expect(portMap.validate, returnsNormally);
      expect(portMap.isConnected, isFalse);
    });

    test('allows the source from its own established connection', () {
      final module = BridgeModule('dut')
        ..createPort('physical', PortDirection.input);
      final interfaceReference = module.addInterface(
        PairInterface(portsFromProvider: [Logic.port('logical')]),
        name: 'interface',
        role: PairRole.consumer,
        connect: false,
      );
      final portMap = module.addPortMap(
        module.port('physical'),
        interfaceReference.port('logical'),
      )
        ..connect()
        ..validate();

      expect(module.inputSource('physical').srcConnection, isNotNull);
      expect(portMap.isConnected, isTrue);
    });

    test('interface reference validates every port map', () {
      final module = BridgeModule('dut')
        ..createPort('physicalA', PortDirection.input)
        ..createPort('physicalB', PortDirection.input);
      final interfaceReference = module.addInterface(
        PairInterface(portsFromProvider: [Logic.port('logical')]),
        name: 'interface',
        role: PairRole.consumer,
        connect: false,
      );
      final validPortMap = module.addPortMap(
        module.port('physicalA'),
        interfaceReference.port('logical'),
      );
      final invalidPortMap = module.addPortMap(
        module.port('physicalB'),
        StandardInterfacePortReference(
          interfaceReference,
          'missingLogical',
        ),
      );

      expect(
        interfaceReference.validate,
        throwsA(isA<PortDoesNotExistException>()),
      );
      expect(validPortMap.isConnected, isFalse);
      expect(invalidPortMap.isConnected, isFalse);
    });
  });
}
