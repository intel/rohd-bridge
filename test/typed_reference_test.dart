// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// typed_reference_test.dart
// Tests for typed reference APIs.
//
// 2026 August 12
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class TestPairInterface extends PairInterface {
  TestPairInterface()
      : super(
          portsFromProvider: [Logic.port('response', 8)],
          portsFromConsumer: [Logic.port('request', 8)],
        );

  @override
  TestPairInterface clone() => TestPairInterface();
}

class OtherPairInterface extends PairInterface {
  OtherPairInterface() : super(portsFromProvider: [Logic.port('other', 8)]);

  @override
  OtherPairInterface clone() => OtherPairInterface();
}

class TestLogicStructure extends LogicStructure {
  final Logic header;
  final Logic payload;

  factory TestLogicStructure({String name = 'testLogicStructure'}) =>
      TestLogicStructure._(
        Logic(name: 'header', width: 2),
        Logic(name: 'payload', width: 6),
        name: name,
      );

  TestLogicStructure._(
    this.header,
    this.payload, {
    required String name,
  }) : super([header, payload], name: name);

  @override
  TestLogicStructure clone({String? name}) =>
      TestLogicStructure(name: name ?? this.name);
}

T _expectType<T>(T value) => value;

BridgeModule _module(String name) =>
    BridgeModule(name, reserveDefinitionName: false);

void main() {
  group('typed ports', () {
    test('checks and exposes the root port type', () {
      final module = _module('module')
        ..addInput('data', null, width: 8)
        ..addInputArray(
          'array',
          null,
          dimensions: [2],
          elementWidth: 4,
        );

      final data = _expectType<TypedPortReference<Logic>>(
        module.typedPort('data'),
      );
      final dataPort = _expectType<Logic>(data.port);
      expect(dataPort.width, 8);

      final array = _expectType<TypedPortReference<LogicArray>>(
        module.typedPort('array'),
      );
      final arrayPort = _expectType<LogicArray>(array.port);
      expect(arrayPort.dimensions, [2]);

      expect(module.tryTypedPort<LogicArray>('data'), isNull);
      expect(
        () => module.typedPort<LogicArray>('data'),
        throwsA(isA<RohdBridgeException>()),
      );
    });

    test('preserves a custom LogicStructure type', () {
      final module = _module('module')
        ..addTypedInput('structured', TestLogicStructure());

      final structured = _expectType<TypedPortReference<TestLogicStructure>>(
        module.typedPort('structured'),
      );
      final structuredPort = _expectType<TestLogicStructure>(structured.port);

      expect(structuredPort.header.width, 2);
      expect(structuredPort.payload.width, 6);
      expect(module.tryTypedPort<LogicArray>('structured'), isNull);
    });

    test('is transparent to existing PortReference APIs', () {
      final producer = _module('producer')..addOutput('data', width: 8);
      final consumer = _module('consumer')..addInput('data', null, width: 8);
      final top = _module('top')
        ..addSubModule(producer)
        ..addSubModule(consumer);

      final driver = _expectType<TypedPortReference<Logic>>(
        producer.typedPort('data'),
      );
      final receiver = _expectType<TypedPortReference<Logic>>(
        consumer.typedPort('data'),
      );
      final untypedDriver = _expectType<PortReference>(driver);

      expect(untypedDriver, producer.port('data'));
      connectPorts(driver, receiver);
      expect(top.subBridgeModules, containsAll([producer, consumer]));
    });

    test('widens slices to PortReference', () {
      final module = _module('module')
        ..addInputArray(
          'array',
          null,
          dimensions: [2],
          elementWidth: 4,
        );
      final array = _expectType<TypedPortReference<LogicArray>>(
        module.typedPort('array'),
      );

      final element = _expectType<PortReference>(array[0]);

      expect(element.portSubset, isA<Logic>());
      expect(element.width, 4);
    });

    test('supports typed interface port lookup', () {
      final module = _module('module')
        ..addInterface(
          TestPairInterface(),
          name: 'bus',
          role: PairRole.provider,
        );
      final interfaceReference =
          module.typedInterface<TestPairInterface>('bus');

      final response = _expectType<TypedPortReference<Logic>>(
        interfaceReference.typedPort('response'),
      );

      expect(response.port.width, 8);
      expect(interfaceReference.tryTypedPort<LogicArray>('response'), isNull);
    });
  });

  group('typed interfaces', () {
    test('supports nullable and checked lookup', () {
      final module = _module('module');
      final added = module.addInterface(
        TestPairInterface(),
        name: 'bus',
        role: PairRole.provider,
      );

      final found = _expectType<InterfaceReference<TestPairInterface>>(
        module.typedInterface('bus'),
      );

      expect(found, added);
      expect(module.tryInterface('bus'), added);
      expect(module.tryInterface('missing'), isNull);
      expect(module.tryTypedInterface<TestPairInterface>('bus'), added);
      expect(module.tryTypedInterface<OtherPairInterface>('bus'), isNull);
      expect(
        () => module.typedInterface<OtherPairInterface>('bus'),
        throwsA(isA<RohdBridgeException>()),
      );
    });

    test('punches up while preserving the interface type', () async {
      final leaf = _module('leaf');
      final leafInterface = leaf.addInterface(
        TestPairInterface(),
        name: 'bus',
        role: PairRole.provider,
      );
      final top = _module('top')..addSubModule(leaf);

      final topInterface = _expectType<InterfaceReference<TestPairInterface>>(
        leafInterface.punchUpToTyped(top),
      );

      expect(topInterface.interface, isA<TestPairInterface>());
      expect(topInterface.internalInterface, isA<TestPairInterface>());
      expect(top.typedInterface<TestPairInterface>('bus'), topInterface);

      await top.build();
    });

    test('punches down while preserving the interface type', () async {
      final top = _module('top');
      final topInterface = top.addInterface(
        TestPairInterface(),
        name: 'bus',
        role: PairRole.provider,
      );
      final leaf = _module('leaf');
      top.addSubModule(leaf);

      final leafInterface = _expectType<InterfaceReference<TestPairInterface>>(
        topInterface.punchDownToTyped(leaf),
      );

      expect(leafInterface.interface, isA<TestPairInterface>());
      expect(leafInterface.internalInterface, isA<TestPairInterface>());
      expect(leaf.typedInterface<TestPairInterface>('bus'), leafInterface);

      await top.build();
    });

    test('pulls up through multiple levels with its type', () async {
      final leaf = _module('leaf');
      final leafInterface = leaf.addInterface(
        TestPairInterface(),
        name: 'bus',
        role: PairRole.consumer,
      );
      final middle = _module('middle')..addSubModule(leaf);
      final top = _module('top')..addSubModule(middle);

      final topInterface = _expectType<InterfaceReference<TestPairInterface>>(
        top.pullUpTypedInterface(leafInterface),
      );

      expect(topInterface.interface, isA<TestPairInterface>());
      expect(
        middle.typedInterface<TestPairInterface>('bus').interface,
        isA<TestPairInterface>(),
      );

      await top.build();
    });

    test('legacy exclusions produce an untyped partial interface', () {
      final leaf = _module('leaf');
      final leafInterface = leaf.addInterface(
        TestPairInterface(),
        name: 'bus',
        role: PairRole.provider,
      );
      final top = _module('top')..addSubModule(leaf);

      final partial = leafInterface.punchUpTo(
        top,
        exceptPorts: {'request'},
      );

      expect(partial.interface, isA<PairInterface>());
      expect(partial.interface, isNot(isA<TestPairInterface>()));
      expect(top.tryTypedInterface<TestPairInterface>('bus'), isNull);
    });
  });
}
