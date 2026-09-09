// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// intermediate_signal_name_test.dart
// Tests for the intermediateSignalName parameter on connectPorts.
//
// 2026 July
// Author: Adin De'Rosier <adin.derosier@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

/// A custom structure used to verify type preservation and field naming.
class _Packet extends LogicStructure {
  /// The naming policy retained for independently emitted fields on cloning.
  final Naming _fieldNaming;

  /// Creates an eight-bit packet with a two-bit header and six-bit payload.
  _Packet({String name = 'packet', Naming naming = Naming.renameable})
      : _fieldNaming = naming,
        super([
          Logic(
              name: naming == Naming.reserved ? '${name}_header' : 'header',
              width: 2,
              naming: naming),
          Logic(
              name: naming == Naming.reserved ? '${name}_payload' : 'payload',
              width: 6,
              naming: naming),
        ], name: name);

  /// Preserves the custom type and fields while applying the requested name.
  @override
  _Packet clone({String? name}) =>
      _Packet(name: name ?? this.name, naming: _fieldNaming);
}

/// A structure whose reserved field name omits its aggregate's name.
class _UnprefixedStructure extends LogicStructure {
  /// Creates a structure with a literal, unprefixed reserved field.
  _UnprefixedStructure({String name = 'unprefixed'})
      : super([Logic(name: 'field', naming: Naming.reserved)], name: name);

  /// Retains the unsupported field naming policy while renaming the aggregate.
  @override
  _UnprefixedStructure clone({String? name}) =>
      _UnprefixedStructure(name: name ?? this.name);
}

/// Sets up a top module with src and dst submodules, each with a
/// dummy output so ROHD can trace both submodules during build.
({BridgeModule top, BridgeModule src, BridgeModule dst}) _buildRig(
    {int width = 8}) {
  final top = BridgeModule('top');
  final src = top.addSubModule(BridgeModule('src'));
  final dst = top.addSubModule(BridgeModule('dst'));

  // dummy outputs so top can trace both submodules during build
  top
    ..pullUpPort(src.createPort('dummy', PortDirection.output))
    ..pullUpPort(dst.createPort('dummy', PortDirection.output));

  return (top: top, src: src, dst: dst);
}

void main() {
  group('intermediateSignalName on connectPorts', () {
    test('strict intermediate names reject unrelated collisions', () async {
      final (:top, :src, :dst) = _buildRig();
      for (final name in ['first', 'second']) {
        final driver = src.createPort(name, PortDirection.output, width: 8);
        final receiver = dst.createPort(name, PortDirection.input, width: 8);
        connectPorts(driver, receiver,
            intermediateSignalName: 'exactName',
            allowIntermediateSignalNameUniquification: false);
      }

      await top.build();
      expect(
          top.generateSynth, throwsA(isA<UnavailableReservedNameException>()));
    });

    for (final selection in ['', '[2:1]']) {
      test('strict array collisions are rejected, selection=$selection',
          () async {
        final (:top, :src, :dst) = _buildRig();
        for (final name in ['first', 'second']) {
          src.createArrayPort(name, PortDirection.output,
              dimensions: [if (selection.isEmpty) 2 else 4, 3],
              elementWidth: 4,
              numUnpackedDimensions: 1);
          final receiver = dst.createArrayPort(name, PortDirection.input,
              dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
          connectPorts(src.port('$name$selection'), receiver,
              intermediateSignalName: 'exactArray',
              allowIntermediateSignalNameUniquification: false);
        }

        await top.build();
        expect(top.generateSynth,
            throwsA(isA<UnavailableReservedNameException>()));
      });
    }

    for (final firstStrict in [false, true]) {
      test('strict fan-out reuse after firstStrict=$firstStrict', () async {
        final (:top, :src, :dst) = _buildRig();
        final driver =
            src.createPort('dataOut', PortDirection.output, width: 8);
        final first = dst.createPort('first', PortDirection.input, width: 8);
        final second = dst.createPort('second', PortDirection.input, width: 8);
        first.gets(driver,
            intermediateSignalName: 'sharedExact',
            allowIntermediateSignalNameUniquification: !firstStrict);
        final intermediate = driver.port.dstConnections
            .singleWhere((signal) => signal.name == 'sharedExact');
        final connections = intermediate.dstConnections.toSet();

        if (!firstStrict) {
          expect(
              () => second.gets(driver,
                  intermediateSignalName: 'sharedExact',
                  allowIntermediateSignalNameUniquification: false),
              throwsA(isA<RohdBridgeException>()));
          expect(intermediate.dstConnections.toSet(), connections);
        } else {
          second.gets(driver,
              intermediateSignalName: 'sharedExact',
              allowIntermediateSignalNameUniquification: false);
        }
        second.gets(driver, intermediateSignalName: 'sharedExact');

        await top.build();
        expect(
            top.internalSignals.where((signal) => signal.name == 'sharedExact'),
            [intermediate]);
        expect(intermediate.naming,
            firstStrict ? Naming.reserved : Naming.renameable);
        expect(top.generateSynth(), isNot(contains('sharedExact_0')));
        driver.port.put(0xAB);
        expect(first.port.value.toInt(), 0xAB);
        expect(second.port.value.toInt(), 0xAB);
      });

      test('strict fan-in reuse after firstStrict=$firstStrict', () async {
        final (:top, :src, :dst) = _buildRig();
        final first = src.createPort('first', PortDirection.inOut, width: 8);
        final second = src.createPort('second', PortDirection.inOut, width: 8);
        final receiver =
            dst.createPort('dataIn', PortDirection.inOut, width: 8);
        connectPorts(first, receiver,
            intermediateSignalName: 'sharedExact',
            allowIntermediateSignalNameUniquification: !firstStrict);
        final connections = second.port.dstConnections.toSet();

        if (!firstStrict) {
          expect(
              () => connectPorts(second, receiver,
                  intermediateSignalName: 'sharedExact',
                  allowIntermediateSignalNameUniquification: false),
              throwsA(isA<RohdBridgeException>()));
          expect(second.port.dstConnections.toSet(), connections);
        } else {
          connectPorts(second, receiver,
              intermediateSignalName: 'sharedExact',
              allowIntermediateSignalNameUniquification: false);
        }
        connectPorts(second, receiver, intermediateSignalName: 'sharedExact');

        await top.build();
        final intermediate = top.internalSignals
            .singleWhere((signal) => signal.name == 'sharedExact');
        expect(intermediate.naming,
            firstStrict ? Naming.reserved : Naming.renameable);
        expect(top.generateSynth(), isNot(contains('sharedExact_0')));
        first.port.put(0xAB);
        second.port.put(0xAB);
        expect(receiver.port.value.toInt(), 0xAB);
      });
    }

    for (final reservedFields in [false, true]) {
      for (final name in ['', 'invalid-name']) {
        test('strict invalid name "$name", structure=$reservedFields', () {
          final (:src, :dst, top: _) = _buildRig();
          if (reservedFields) {
            src.addTypedOutput(
                'dataOut',
                ({name = 'packet'}) =>
                    _Packet(name: name, naming: Naming.reserved));
            dst.addTypedInput('dataIn', _Packet());
          } else {
            src.createPort('dataOut', PortDirection.output, width: 8);
            dst.createPort('dataIn', PortDirection.input, width: 8);
          }
          expect(
              () => connectPorts(src.port('dataOut'), dst.port('dataIn'),
                  intermediateSignalName: name,
                  allowIntermediateSignalNameUniquification: false),
              throwsA(name.isEmpty
                  ? isA<EmptyReservedNameException>()
                  : isA<InvalidReservedNameException>()));
        });
      }
    }

    for (final collision in [false, true]) {
      test('strict structure reserves emitted fields, collision=$collision',
          () async {
        final (:top, :src, :dst) = _buildRig();
        src.addTypedOutput(
            'dataOut',
            ({name = 'packet'}) =>
                _Packet(name: name, naming: Naming.reserved));
        for (final name in ['first', 'second']) {
          dst.addTypedInput(name, _Packet());
          connectPorts(src.port('dataOut'), dst.port(name),
              intermediateSignalName: 'exactPacket',
              allowIntermediateSignalNameUniquification: false);
        }
        if (collision) {
          top.createPort('exactPacket_header', PortDirection.output, width: 2);
        }

        await top.build();
        final intermediate = top.internalSignals
            .whereType<_Packet>()
            .singleWhere((signal) => signal.name == 'exactPacket');
        expect(
            intermediate.elements
                .every((field) => field.naming == Naming.reserved),
            isTrue);
        if (collision) {
          expect(top.generateSynth,
              throwsA(isA<UnavailableReservedNameException>()));
        } else {
          final sv = top.generateSynth();
          expect(sv, contains('exactPacket_header'));
          expect(sv, contains('exactPacket_payload'));
          expect(sv, isNot(contains('exactPacket_header_0')));
          src.output('dataOut').put(0xAB);
          expect(dst.input('first').value.toInt(), 0xAB);
          expect(dst.input('second').value.toInt(), 0xAB);
        }
      });
    }

    for (final isNet in [false, true]) {
      for (final unpacked in [0, 1, 2]) {
        test('strict whole array, unpacked=$unpacked, net=$isNet', () async {
          final (:top, :src, :dst) = _buildRig();
          final driver = src.createArrayPort(
              'dataOut', isNet ? PortDirection.inOut : PortDirection.output,
              dimensions: [2, 3],
              elementWidth: 4,
              numUnpackedDimensions: unpacked);
          final receiver = dst.createArrayPort(
              'dataIn', isNet ? PortDirection.inOut : PortDirection.input,
              dimensions: [2, 3],
              elementWidth: 4,
              numUnpackedDimensions: unpacked);

          connectPorts(driver, receiver,
              intermediateSignalName: 'exactArray',
              allowIntermediateSignalNameUniquification: false);

          await top.build();
          final intermediate = top.internalSignals
              .whereType<LogicArray>()
              .singleWhere((signal) => signal.name == 'exactArray');
          expect(intermediate.dimensions, [2, 3]);
          expect(intermediate.elementWidth, 4);
          expect(intermediate.numUnpackedDimensions, unpacked);
          expect(intermediate.isNet, isNet);
          expect(intermediate.naming, Naming.reserved);
          final sv = top.generateSynth();
          expect(sv, matches(RegExp(r'\.dataOut\s*\(\s*exactArray\s*\)')));
          expect(sv, matches(RegExp(r'\.dataIn\s*\(\s*exactArray\s*\)')));
          driver.port.put(0xABCDEF);
          expect(receiver.port.value.toInt(), 0xABCDEF);
        });
      }
    }

    test('strict structure rejects renameable clone without connecting',
        () async {
      final (:src, :dst, :top) = _buildRig();
      src.addTypedOutput('dataOut', _Packet.new);
      dst.addTypedInput('dataIn', _Packet());
      final driver = src.output('dataOut') as _Packet;
      final connections = driver.leafElements
          .map((field) => field.dstConnections.toSet())
          .toList();

      expect(
          () => connectPorts(src.port('dataOut'), dst.port('dataIn'),
              intermediateSignalName: 'exactPacket',
              allowIntermediateSignalNameUniquification: false),
          throwsA(isA<RohdBridgeException>()));
      expect(driver.leafElements.map((field) => field.dstConnections.toSet()),
          connections);
      connectPorts(src.port('dataOut'), dst.port('dataIn'),
          intermediateSignalName: 'exactPacket');
      await top.build();
      expect(top.generateSynth(), contains('exactPacket_header'));
    });

    for (final names in [
      (
        description: 'receiver path only',
        driver: null,
        receiver: 'receiverWire',
        intermediate: null,
        expected: 'receiverWire',
      ),
      (
        description: 'driver path only',
        driver: 'driverWire',
        receiver: null,
        intermediate: null,
        expected: 'driverWire',
      ),
      (
        description: 'receiver path overrides driver path',
        driver: 'driverWire',
        receiver: 'receiverWire',
        intermediate: null,
        expected: 'receiverWire',
      ),
      (
        description: 'explicit intermediate overrides both paths',
        driver: 'driverWire',
        receiver: 'receiverWire',
        intermediate: 'explicitWire',
        expected: 'explicitWire',
      ),
      (
        description: 'no supplied names keeps the direct connection',
        driver: null,
        receiver: null,
        intermediate: null,
        expected: null,
      ),
    ]) {
      for (final allowUniquification in [true, false]) {
        test(
            'path name fallback: ${names.description}, '
            'allowUniquification=$allowUniquification', () async {
          final (:top, :src, :dst) = _buildRig();
          src.createPort('myPortOut', PortDirection.output, width: 8);
          dst.createPort('myPortIn', PortDirection.input, width: 8);

          connectPorts(src.port('myPortOut'), dst.port('myPortIn'),
              driverPathNewPortName: names.driver,
              receiverPathNewPortName: names.receiver,
              intermediateSignalName: names.intermediate,
              allowIntermediateSignalNameUniquification: allowUniquification);

          await top.build();
          final sv = top.generateSynth();
          if (names.expected == null) {
            expect(dst.inputSource('myPortIn').srcConnections,
                contains(src.output('myPortOut')));
          } else {
            final intermediate = top.internalSignals
                .singleWhere((signal) => signal.name == names.expected);
            expect(intermediate.naming,
                allowUniquification ? Naming.renameable : Naming.reserved);
            expect(
                sv,
                matches(
                    RegExp('\\.myPortOut\\s*\\(\\s*${names.expected}\\s*\\)')));
            expect(
                sv,
                matches(
                    RegExp('\\.myPortIn\\s*\\(\\s*${names.expected}\\s*\\)')));
          }
          expect(src.outputs.keys, contains('myPortOut'));
          expect(dst.inputs.keys, contains('myPortIn'));

          src.output('myPortOut').put(0xAB);
          expect(dst.input('myPortIn').value.toInt(), 0xAB);
        });
      }
    }

    test('path name fallback: nested fan-out reuses the named route', () async {
      final source = BridgeModule('source')
        ..createPort('dataOut', PortDirection.output, width: 8);
      final first = BridgeModule('first')
        ..createPort('dataIn', PortDirection.input, width: 8);
      final second = BridgeModule('second')
        ..createPort('dataIn', PortDirection.input, width: 8);
      final sourceParent = BridgeModule('sourceParent')..addSubModule(source);
      final receiverParent = BridgeModule('receiverParent')
        ..addSubModule(first)
        ..addSubModule(second);
      final top = BridgeModule('top')
        ..addSubModule(sourceParent)
        ..addSubModule(receiverParent)
        ..pullUpPort(sourceParent.createPort('dummy', PortDirection.output));

      for (final receiver in [first, first, second]) {
        connectPorts(source.port('dataOut'), receiver.port('dataIn'),
            driverPathNewPortName: 'driverRoute',
            receiverPathNewPortName: 'receiverRoute');
      }

      await top.build();
      final sv = top.generateSynth();
      expect(receiverParent.inputs.keys, ['receiverRoute']);
      expect(
          sourceParent
              .output('driverRoute')
              .dstConnections
              .where((signal) => signal.name == 'receiverRoute'),
          hasLength(1));
      expect(sv, isNot(contains('receiverRoute_0')));
      expect(sv, matches(RegExp(r'\.driverRoute\s*\(\s*receiverRoute\s*\)')));
      expect(sv, matches(RegExp(r'\.receiverRoute\s*\(\s*receiverRoute\s*\)')));

      source.output('dataOut').put(0xAB);
      expect(first.input('dataIn').value.toInt(), 0xAB);
      expect(second.input('dataIn').value.toInt(), 0xAB);
    });

    test('path name fallback: collisions keep independent nets distinct',
        () async {
      final (:top, :src, :dst) = _buildRig();
      src
        ..createPort('firstOut', PortDirection.output, width: 8)
        ..createPort('secondOut', PortDirection.output, width: 8);
      dst
        ..createPort('firstIn', PortDirection.input, width: 8)
        ..createPort('secondIn', PortDirection.input, width: 8);

      connectPorts(src.port('firstOut'), dst.port('firstIn'),
          receiverPathNewPortName: 'sharedWire');
      connectPorts(src.port('secondOut'), dst.port('secondIn'),
          receiverPathNewPortName: 'sharedWire');

      await top.build();
      final sv = top.generateSynth();
      final firstNet = RegExp(r'\.firstIn\s*\(\s*(sharedWire(?:_\d+)?)\s*\)')
          .firstMatch(sv)!
          .group(1)!;
      final secondNet = RegExp(r'\.secondIn\s*\(\s*(sharedWire(?:_\d+)?)\s*\)')
          .firstMatch(sv)!
          .group(1)!;
      expect(firstNet, isNot(secondNet));
      expect(sv, matches(RegExp('\\.firstOut\\s*\\(\\s*$firstNet\\s*\\)')));
      expect(sv, matches(RegExp('\\.secondOut\\s*\\(\\s*$secondNet\\s*\\)')));

      src.output('firstOut').put(0xAB);
      src.output('secondOut').put(0xCD);
      expect(dst.input('firstIn').value.toInt(), 0xAB);
      expect(dst.input('secondIn').value.toInt(), 0xCD);
    });

    for (final unpacked in [0, 1, 2]) {
      for (final isNet in [false, true]) {
        test('whole array name, unpacked=$unpacked, net=$isNet', () async {
          final (:top, :src, :dst) = _buildRig();
          final driver = src.createArrayPort(
              'dataOut', isNet ? PortDirection.inOut : PortDirection.output,
              dimensions: [2, 3],
              elementWidth: 4,
              numUnpackedDimensions: unpacked);
          final receiver = dst.createArrayPort(
              'dataIn', isNet ? PortDirection.inOut : PortDirection.input,
              dimensions: [2, 3],
              elementWidth: 4,
              numUnpackedDimensions: unpacked);

          connectPorts(driver, receiver, intermediateSignalName: 'namedArray');

          await top.build();
          final intermediate = top.internalSignals
              .whereType<LogicArray>()
              .singleWhere((signal) => signal.name == 'namedArray');
          expect(intermediate.dimensions, [2, 3]);
          expect(intermediate.elementWidth, 4);
          expect(intermediate.numUnpackedDimensions, unpacked);
          expect(intermediate.isNet, isNet);
          final sv = top.generateSynth();
          expect(sv, matches(RegExp(r'\.dataOut\s*\(\s*namedArray\s*\)')));
          expect(sv, matches(RegExp(r'\.dataIn\s*\(\s*namedArray\s*\)')));

          driver.port.put(0xABCDEF);
          expect(receiver.port.value.toInt(), 0xABCDEF);
        });
      }
    }

    test('strict structure rejects unprefixed reserved fields', () {
      final (:src, :dst, top: _) = _buildRig();
      src.addTypedOutput('dataOut', _UnprefixedStructure.new);
      dst.addTypedInput('dataIn', _UnprefixedStructure());
      expect(
          () => connectPorts(src.port('dataOut'), dst.port('dataIn'),
              intermediateSignalName: 'exactStructure',
              allowIntermediateSignalNameUniquification: false),
          throwsA(isA<RohdBridgeException>()));
    });

    for (final isNet in [false, true]) {
      test('aggregate fan-out reuses the intermediate, net=$isNet', () async {
        final (:top, :src, :dst) = _buildRig();
        final driver = src.createArrayPort(
            'dataOut', isNet ? PortDirection.inOut : PortDirection.output,
            dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
        for (final name in ['first', 'second']) {
          final receiver = dst.createArrayPort(
              name, isNet ? PortDirection.inOut : PortDirection.input,
              dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
          connectPorts(driver, receiver, intermediateSignalName: 'sharedArray');
        }

        await top.build();
        expect(
            top.internalSignals.where((signal) => signal.name == 'sharedArray'),
            hasLength(1));
        final sv = top.generateSynth();
        expect(sv, matches(RegExp(r'\.first\s*\(\s*sharedArray\s*\)')));
        expect(sv, matches(RegExp(r'\.second\s*\(\s*sharedArray\s*\)')));
        driver.port.put(0xABCDEF);
        expect(dst.port('first').port.value.toInt(), 0xABCDEF);
        expect(dst.port('second').port.value.toInt(), 0xABCDEF);
      });
    }

    test('direct structure connection clones the custom type and name',
        () async {
      final (:top, :src, :dst) = _buildRig();
      src.addTypedOutput('dataOut', _Packet.new);
      dst
        ..addTypedInput('first', _Packet())
        ..addTypedInput('second', _Packet());
      for (final name in ['first', 'second']) {
        connectPorts(src.port('dataOut'), dst.port(name),
            intermediateSignalName: 'namedPacket');
      }

      await top.build();
      final intermediate = top.internalSignals
          .whereType<_Packet>()
          .singleWhere((signal) => signal.name == 'namedPacket');
      expect(intermediate.elements.map((element) => element.width), [2, 6]);
      final sv = top.generateSynth();
      expect(sv, contains('namedPacket_header'));
      expect(sv, contains('namedPacket_payload'));
      src.output('dataOut').put(0xAB);
      expect(dst.input('first').value.toInt(), 0xAB);
      expect(dst.input('second').value.toInt(), 0xAB);
    });

    for (final unpacked in [0, 1, 2]) {
      for (final isNet in [false, true]) {
        for (final selection in ['[1]', '[2:1]']) {
          for (final allowUniquification in [true, false]) {
            test(
                'array selection $selection, unpacked=$unpacked, net=$isNet, '
                'allowUniquification=$allowUniquification', () async {
              final (:top, :src, :dst) = _buildRig();
              final driver = src.createArrayPort(
                  'dataOut', isNet ? PortDirection.inOut : PortDirection.output,
                  dimensions: [4, 3],
                  elementWidth: 4,
                  numUnpackedDimensions: unpacked);
              final dimensions = selection == '[1]' ? [3] : [2, 3];
              final selectedUnpacked =
                  selection == '[1]' && unpacked > 0 ? unpacked - 1 : unpacked;
              for (final name in ['first', 'second']) {
                final receiver = dst.createArrayPort(
                    name, isNet ? PortDirection.inOut : PortDirection.input,
                    dimensions: dimensions,
                    elementWidth: 4,
                    numUnpackedDimensions: selectedUnpacked);
                connectPorts(src.port('dataOut$selection'), receiver,
                    intermediateSignalName: 'selectedArray',
                    allowIntermediateSignalNameUniquification:
                        allowUniquification);
              }

              await top.build();
              final intermediate = top.internalSignals
                  .whereType<LogicArray>()
                  .singleWhere((signal) => signal.name == 'selectedArray');
              expect(intermediate.dimensions, dimensions);
              expect(intermediate.elementWidth, 4);
              expect(intermediate.numUnpackedDimensions, selectedUnpacked);
              expect(intermediate.isNet, isNet);
              expect(intermediate.naming,
                  allowUniquification ? Naming.renameable : Naming.reserved);
              final sv = top.generateSynth();
              expect(sv, contains('selectedArray'));
              expect(sv, isNot(contains('selectedArray_0')));
              driver.port.put(0x123456789ABC);
              final expected = selection == '[1]' ? 0x789 : 0x456789;
              expect(dst.port('first').port.value.toInt(), expected);
              expect(dst.port('second').port.value.toInt(), expected);
            });
          }
        }
      }
    }

    test('bit slices within array elements retain a packed name', () async {
      final (:top, :src, :dst) = _buildRig();
      final driver = src.createArrayPort('dataOut', PortDirection.output,
          dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
      dst.createArrayPort('dataIn', PortDirection.input,
          dimensions: [2], elementWidth: 8, numUnpackedDimensions: 1);
      final receiver = dst.port('dataIn[1][5:3]');
      connectPorts(src.port('dataOut[1][2][3:1]'), receiver,
          intermediateSignalName: 'selectedBits',
          allowIntermediateSignalNameUniquification: false);

      await top.build();
      final intermediate = top.internalSignals
          .singleWhere((signal) => signal.name == 'selectedBits');
      expect(intermediate, isNot(isA<LogicStructure>()));
      expect(intermediate.width, 3);
      expect(intermediate.naming, Naming.reserved);
      expect(top.generateSynth(), contains('selectedBits'));
      driver.port.put(0xABCDEF);
      expect(receiver.portSubsetLogic.value.toInt(), 5);
    });

    test('array slice backed by a packed input source keeps its name',
        () async {
      final (:top, :src, :dst) = _buildRig();
      final driver = src.createArrayPort('dataOut', PortDirection.output,
          dimensions: [4, 3], elementWidth: 4, numUnpackedDimensions: 1);
      dst.addInputArray('dataIn', Logic(width: 48),
          dimensions: [4, 3], elementWidth: 4, numUnpackedDimensions: 1);
      final receiver = dst.port('dataIn[2:1]');
      connectPorts(src.port('dataOut[2:1]'), receiver,
          intermediateSignalName: 'packedSourceSelection',
          allowIntermediateSignalNameUniquification: false);

      await top.build();
      expect(
          top.internalSignals
              .whereType<LogicArray>()
              .singleWhere((signal) => signal.name == 'packedSourceSelection')
              .naming,
          Naming.reserved);
      expect(top.generateSynth(), contains('packedSourceSelection'));
      driver.port.put(0x123456789ABC);
      expect(receiver.portSubsetLogic.value.toInt(), 0x456789);
    });

    test('different array selections with equal names remain independent',
        () async {
      final (:top, :src, :dst) = _buildRig();
      final driver = src.createArrayPort('dataOut', PortDirection.output,
          dimensions: [4, 3], elementWidth: 4, numUnpackedDimensions: 1);
      for (final (name, selection) in [
        ('first', '[1:0]'),
        ('second', '[2:1]')
      ]) {
        final receiver = dst.createArrayPort(name, PortDirection.input,
            dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
        connectPorts(src.port('dataOut$selection'), receiver,
            intermediateSignalName: 'sameName');
      }

      await top.build();
      expect(top.internalSignals.where((signal) => signal.name == 'sameName'),
          hasLength(2));
      final sv = top.generateSynth();
      expect(sv, contains('sameName_0'));
      driver.port.put(0x123456789ABC);
      expect(dst.input('first').value.toInt(), 0x789ABC);
      expect(dst.input('second').value.toInt(), 0x456789);
    });

    test('unrelated arrays with equal names remain independent', () async {
      final (:top, :src, :dst) = _buildRig();
      for (final name in ['first', 'second']) {
        final driver = src.createArrayPort(name, PortDirection.output,
            dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
        final receiver = dst.createArrayPort(name, PortDirection.input,
            dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
        connectPorts(driver, receiver, intermediateSignalName: 'sameName');
      }

      await top.build();
      expect(top.internalSignals.where((signal) => signal.name == 'sameName'),
          hasLength(2));
      expect(top.generateSynth(), contains('sameName_0'));
      src.output('first').put(0x123456);
      src.output('second').put(0xABCDEF);
      expect(dst.input('first').value.toInt(), 0x123456);
      expect(dst.input('second').value.toInt(), 0xABCDEF);
    });

    test('hierarchical structure connections retain packed path ports',
        () async {
      final top = BridgeModule('top');
      final srcParent = top.addSubModule(BridgeModule('srcParent'));
      final dstParent = top.addSubModule(BridgeModule('dstParent'));
      final src = srcParent.addSubModule(BridgeModule('src'))
        ..addTypedOutput('dataOut', _Packet.new);
      final dst = dstParent.addSubModule(BridgeModule('dst'))
        ..addTypedInput('dataIn', _Packet());
      top
        ..pullUpPort(src.createPort('dummy', PortDirection.output))
        ..pullUpPort(dst.createPort('dummy', PortDirection.output));
      connectPorts(src.port('dataOut'), dst.port('dataIn'),
          driverPathNewPortName: 'driverPath',
          receiverPathNewPortName: 'receiverPath',
          intermediateSignalName: 'packedPacket');

      await top.build();
      expect(srcParent.output('driverPath'), isNot(isA<LogicStructure>()));
      expect(dstParent.input('receiverPath'), isNot(isA<LogicStructure>()));
      final intermediate = top.internalSignals
          .singleWhere((signal) => signal.name == 'packedPacket');
      expect(intermediate, isNot(isA<LogicStructure>()));
      expect(intermediate.width, 8);
      final sv = top.generateSynth();
      expect(sv, matches(RegExp(r'\.driverPath\s*\(\s*packedPacket\s*\)')));
      expect(sv, matches(RegExp(r'\.receiverPath\s*\(\s*packedPacket\s*\)')));
      src.output('dataOut').put(0xAB);
      expect(dst.input('dataIn').value.toInt(), 0xAB);
    });

    for (final driverSelection in ['', '[2:1]']) {
      for (final receiverSelection in ['', '[2:1]']) {
        test(
            'array fan-in: driver=$driverSelection receiver=$receiverSelection',
            () async {
          final (:top, :src, :dst) = _buildRig();
          dst.createArrayPort('dataIn', PortDirection.inOut,
              dimensions: [if (receiverSelection.isEmpty) 2 else 4, 3],
              elementWidth: 4,
              numUnpackedDimensions: 1);
          for (final name in ['first', 'second']) {
            src.createArrayPort(name, PortDirection.inOut,
                dimensions: [if (driverSelection.isEmpty) 2 else 4, 3],
                elementWidth: 4,
                numUnpackedDimensions: 1);
            connectPorts(src.port('$name$driverSelection'),
                dst.port('dataIn$receiverSelection'),
                intermediateSignalName: 'sharedBus');
          }

          await top.build();
          expect(
              top.internalSignals.where((signal) => signal.name == 'sharedBus'),
              hasLength(1));
          expect(top.generateSynth(), isNot(contains('sharedBus_0')));
          src.inOut('first').put(0x123456);
          final expected = driverSelection.isEmpty ? 0x123456 : 0x123;
          final receiverStart = receiverSelection.isEmpty ? 0 : 12;
          expect(
              dst
                  .inOut('dataIn')
                  .value
                  .getRange(receiverStart, receiverStart + 24)
                  .toInt(),
              expected);
        });
      }
    }

    test('distinct requested array names are retained for one driver',
        () async {
      final (:top, :src, :dst) = _buildRig();
      final driver = src.createArrayPort('dataOut', PortDirection.output,
          dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
      for (final name in ['first', 'second']) {
        final receiver = dst.createArrayPort(name, PortDirection.input,
            dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
        connectPorts(driver, receiver, intermediateSignalName: '${name}Bus');
      }

      await top.build();
      final sv = top.generateSynth();
      for (final name in ['firstBus', 'secondBus']) {
        expect(top.internalSignals.where((signal) => signal.name == name),
            hasLength(1));
        expect(sv, contains(name));
      }
      driver.port.put(0xABCDEF);
      expect(dst.input('first').value.toInt(), 0xABCDEF);
      expect(dst.input('second').value.toInt(), 0xABCDEF);
    });

    test('cross-field structure slices retain a packed intermediate name',
        () async {
      final (:top, :src, :dst) = _buildRig();
      src.addTypedOutput('dataOut', _Packet.new);
      dst.addTypedInput('dataIn', _Packet());
      connectPorts(src.port('dataOut[5:1]'), dst.port('dataIn[6:2]'),
          intermediateSignalName: 'packetBits');

      await top.build();
      final intermediate = top.internalSignals
          .singleWhere((signal) => signal.name == 'packetBits');
      expect(intermediate, isNot(isA<LogicStructure>()));
      expect(intermediate.width, 5);
      expect(top.generateSynth(), contains('packetBits'));
      src.output('dataOut').put(0xAB);
      expect(dst.input('dataIn').value.getRange(2, 7).toInt(), 0x15);
    });

    test('does not adopt manually added intermediate signals', () async {
      final (:top, :src, :dst) = _buildRig();
      final driver = src.createPort('dataOut', PortDirection.output, width: 8);
      final receiver = dst.createPort('dataIn', PortDirection.input, width: 8);
      final manual = Logic(name: 'sharedName', width: 8)..gets(driver.port);
      top.addOutput('manualObserver', width: 8) <= manual;

      connectPorts(driver, receiver, intermediateSignalName: 'sharedName');

      await top.build();
      final intermediates = top.internalSignals
          .where((signal) => signal.name == 'sharedName')
          .toList();
      expect(intermediates, hasLength(2));
      expect(dst.inputSource('dataIn').srcConnections, isNot(contains(manual)));
      expect(top.generateSynth(), contains('sharedName'));
      driver.port.put(0xAB);
      expect(receiver.port.value.toInt(), 0xAB);
      expect(top.output('manualObserver').value.toInt(), 0xAB);
    });

    test('registry normalizes independently constructed slice references',
        () async {
      final (:top, :src, :dst) = _buildRig();
      final driver = src.createPort('dataOut', PortDirection.output, width: 8);
      final first = dst.createPort('first', PortDirection.input, width: 4);
      final second = dst.createPort('second', PortDirection.input, width: 4);
      connectPorts(src.port('dataOut[5:2]'), first,
          intermediateSignalName: 'sliceName');
      connectPorts(driver.slice(5, 2), second,
          intermediateSignalName: 'sliceName');

      await top.build();
      expect(top.internalSignals.where((signal) => signal.name == 'sliceName'),
          hasLength(1));
      driver.port.put(0xAB);
      expect(first.port.value.toInt(), 0xA);
      expect(second.port.value.toInt(), 0xA);
    });

    test('registry distinguishes array shapes covering the same bits',
        () async {
      final (:top, :src, :dst) = _buildRig();
      final driver = src.createArrayPort('dataOut', PortDirection.output,
          dimensions: [1, 3], elementWidth: 4, numUnpackedDimensions: 1);
      for (final name in ['first', 'second']) {
        final whole = dst.createArrayPort('${name}Whole', PortDirection.input,
            dimensions: [1, 3], elementWidth: 4, numUnpackedDimensions: 1);
        final row = dst.createArrayPort('${name}Row', PortDirection.input,
            dimensions: [3], elementWidth: 4);
        connectPorts(driver, whole, intermediateSignalName: 'arrayName');
        connectPorts(src.port('dataOut[0]'), row,
            intermediateSignalName: 'arrayName');
      }

      await top.build();
      final arrays = top.internalSignals
          .whereType<LogicArray>()
          .where((signal) => signal.name == 'arrayName');
      expect(
          arrays.map((signal) => signal.dimensions),
          unorderedEquals([
            [1, 3],
            [3]
          ]));
      driver.port.put(0xABC);
      for (final name in [
        'firstWhole',
        'firstRow',
        'secondWhole',
        'secondRow'
      ]) {
        expect(dst.input(name).value.toInt(), 0xABC);
      }
    });

    test('registry separates internal and external connection scopes',
        () async {
      final (:top, :src, :dst) = _buildRig();
      final driver = src.createPort('dataOut', PortDirection.output, width: 8);
      final loopback =
          src.createPort('loopback', PortDirection.input, width: 8);
      final passthrough =
          src.createPort('passthrough', PortDirection.output, width: 8);
      final sibling = dst.createPort('dataIn', PortDirection.input, width: 8);
      connectPorts(driver, loopback, intermediateSignalName: 'scopedName');
      connectPorts(driver, passthrough,
          sameModuleConnectionType: SameModuleConnectionType.passthrough,
          intermediateSignalName: 'scopedName');
      connectPorts(driver, sibling, intermediateSignalName: 'scopedName');

      final externalSignal = src.inputSource('loopback').srcConnections.single;
      final internalSignal = passthrough.port.srcConnections.single;
      expect(identical(internalSignal, externalSignal), isFalse);
      expect(
          dst.inputSource('dataIn').srcConnections, contains(externalSignal));
      await top.build();
      expect(top.generateSynth(), contains('scopedName'));
      driver.port.put(0xAB);
      expect(loopback.port.value.toInt(), 0xAB);
      expect(passthrough.port.value.toInt(), 0xAB);
      expect(sibling.port.value.toInt(), 0xAB);
    });

    for (final fanInFirst in [false, true]) {
      test('registry interleaved reuse, fanInFirst=$fanInFirst', () async {
        final (:top, :src, :dst) = _buildRig();
        for (final name in ['first', 'second']) {
          src.createArrayPort(name, PortDirection.inOut,
              dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
          dst.createArrayPort(name, PortDirection.inOut,
              dimensions: [2, 3], elementWidth: 4, numUnpackedDimensions: 1);
        }
        final connections = fanInFirst
            ? [('first', 'first'), ('second', 'first'), ('second', 'second')]
            : [('first', 'first'), ('first', 'second'), ('second', 'second')];
        for (final (driverName, receiverName) in connections) {
          connectPorts(src.port(driverName), dst.port(receiverName),
              intermediateSignalName: 'sharedBus');
        }

        await top.build();
        expect(
            top.internalSignals.where((signal) => signal.name == 'sharedBus'),
            hasLength(1));
        expect(top.generateSynth(), isNot(contains('sharedBus_0')));
        src.inOut('first').put(0xABCDEF);
        expect(src.inOut('second').value.toInt(), 0xABCDEF);
        expect(dst.inOut('first').value.toInt(), 0xABCDEF);
        expect(dst.inOut('second').value.toInt(), 0xABCDEF);
      });
    }

    test('sibling logic ports: net appears by name in generated SV', () async {
      final (:top, :src, :dst) = _buildRig();

      src.createPort('myPortOut', PortDirection.output, width: 8);
      dst.createPort('myPortIn', PortDirection.input, width: 8);

      connectPorts(src.port('myPortOut'), dst.port('myPortIn'),
          intermediateSignalName: 'myNamedNet');

      await top.build();
      final sv = top.generateSynth();
      expect(sv, contains('myNamedNet'));

      // The intermediate signal should exist in top's internal signals,
      // driven by src's output and driving dst's input source.
      final intermediate =
          top.internalSignals.firstWhere((s) => s.name == 'myNamedNet');
      expect(intermediate.srcConnections, contains(src.output('myPortOut')));
      expect(
          dst.inputSource('myPortIn').srcConnections, contains(intermediate));

      src.output('myPortOut').put(0xAB);
      expect(dst.input('myPortIn').value.toInt(), equals(0xAB));
    });

    test('same-module loopback uses the requested net name', () async {
      final child = BridgeModule('child')
        ..createPort('myPortOut', PortDirection.output, width: 8)
        ..createPort('myPortIn', PortDirection.input, width: 8);
      final top = BridgeModule('top')
        ..addSubModule(child)
        ..pullUpPort(child.createPort('dummy', PortDirection.output));

      connectPorts(child.port('myPortOut'), child.port('myPortIn'),
          intermediateSignalName: 'myLoopbackNet',
          allowIntermediateSignalNameUniquification: false);

      await top.build();
      final sv = top.generateSynth();

      expect(
          top.internalSignals
              .singleWhere((signal) => signal.name == 'myLoopbackNet')
              .naming,
          Naming.reserved);
      expect(sv, matches(RegExp(r'logic\s*\[7:0\]\s*myLoopbackNet')));
      expect(sv, matches(RegExp(r'\.myPortOut\s*\(\s*myLoopbackNet\s*\)')));
      expect(sv, matches(RegExp(r'\.myPortIn\s*\(\s*myLoopbackNet\s*\)')));
    });

    test('same-module passthrough uses the requested net name', () async {
      final child = BridgeModule('child')
        ..createPort('myPortIn', PortDirection.input, width: 8)
        ..createPort('myPortOut', PortDirection.output, width: 8);
      final top = BridgeModule('top')
        ..addSubModule(child)
        ..pullUpPort(child.createPort('dummy', PortDirection.output));

      connectPorts(child.port('myPortIn'), child.port('myPortOut'),
          sameModuleConnectionType: SameModuleConnectionType.passthrough,
          intermediateSignalName: 'myPassthroughNet',
          allowIntermediateSignalNameUniquification: false);

      await top.build();
      final sv = top.generateSynth();

      expect(child.internalSignals.map((signal) => signal.name),
          contains('myPassthroughNet'));
      expect(
          child.internalSignals
              .singleWhere((signal) => signal.name == 'myPassthroughNet')
              .naming,
          Naming.reserved);
      expect(sv, matches(RegExp(r'logic\s*\[7:0\]\s*myPassthroughNet')));

      child.input('myPortIn').put(0xAB);
      expect(child.output('myPortOut').value.toInt(), equals(0xAB));
    });

    test('net name appears in portmap for both submodules', () async {
      final (:top, :src, :dst) = _buildRig(width: 4);

      src.createPort('myPortOut', PortDirection.output, width: 4);
      dst.createPort('myPortIn', PortDirection.input, width: 4);

      connectPorts(src.port('myPortOut'), dst.port('myPortIn'),
          intermediateSignalName: 'sharedWire');

      await top.build();
      final sv = top.generateSynth();
      expect(sv, contains('sharedWire'));
      // The net should appear in both submodules' portmaps.
      expect(sv, matches(RegExp(r'\.myPortOut\s*\(\s*sharedWire\s*\)')));
      expect(sv, matches(RegExp(r'\.myPortIn\s*\(\s*sharedWire\s*\)')));

      src.output('myPortOut').put(0xA);
      expect(dst.input('myPortIn').value.toInt(), equals(0xA));
    });

    for (final exportFirst in [true, false]) {
      test(
          'exported top port is reused as the named sibling signal '
          '${exportFirst ? 'before' : 'after'} the sibling connection',
          () async {
        final top = BridgeModule('top');
        final src = top.addSubModule(BridgeModule('src'))
          ..createPort('myPortOut', PortDirection.output, width: 8);
        final dst = top.addSubModule(BridgeModule('dst'))
          ..createPort('myPortIn', PortDirection.input, width: 8);

        void exportSignal() =>
            top.pullUpPort(src.port('myPortOut'), newPortName: 'explicit_name');
        void connectSiblings() =>
            connectPorts(src.port('myPortOut'), dst.port('myPortIn'),
                intermediateSignalName: 'explicit_name');

        if (exportFirst) {
          exportSignal();
          connectSiblings();
        } else {
          connectSiblings();
          exportSignal();
        }

        await top.build();
        final sv = top.generateSynth();

        expect(sv, isNot(contains('explicit_name_0')));
        expect(sv, matches(RegExp(r'\.myPortOut\s*\(\s*explicit_name\s*\)')));
        expect(sv, matches(RegExp(r'\.myPortIn\s*\(\s*explicit_name\s*\)')));

        src.output('myPortOut').put(0xAB);
        expect(top.output('explicit_name').value.toInt(), equals(0xAB));
        expect(dst.input('myPortIn').value.toInt(), equals(0xAB));
      },
          skip: 'Pending release of ROHD PR '
              'https://github.com/intel/rohd/pull/712');
    }

    for (final exportFirst in [true, false]) {
      test(
          'exported top inout is reused as the named sibling signal '
          '${exportFirst ? 'before' : 'after'} the sibling connection',
          () async {
        final top = BridgeModule('top');
        final src = top.addSubModule(BridgeModule('src'))
          ..createPort('myPort', PortDirection.inOut, width: 8);
        final dst = top.addSubModule(BridgeModule('dst'))
          ..createPort('myPort', PortDirection.inOut, width: 8);

        void exportSignal() =>
            top.pullUpPort(src.port('myPort'), newPortName: 'explicit_name');
        void connectSiblings() =>
            connectPorts(src.port('myPort'), dst.port('myPort'),
                intermediateSignalName: 'explicit_name');

        if (exportFirst) {
          exportSignal();
          connectSiblings();
        } else {
          connectSiblings();
          exportSignal();
        }

        await top.build();
        final sv = top.generateSynth();

        expect(sv, isNot(contains('explicit_name_0')));
        expect(sv, matches(RegExp(r'\.myPort\s*\(\s*explicit_name\s*\)')));

        src.inOut('myPort').put(0xAB);
        expect(top.inOut('explicit_name').value.toInt(), equals(0xAB));
        expect(dst.inOut('myPort').value.toInt(), equals(0xAB));
      },
          skip: 'Pending release of ROHD PR '
              'https://github.com/intel/rohd/pull/712');
    }

    test('without intermediateSignalName: connection works normally', () async {
      final (:top, :src, :dst) = _buildRig(width: 4);

      src.createPort('myPortOut', PortDirection.output, width: 4);
      dst.createPort('myPortIn', PortDirection.input, width: 4);

      connectPorts(src.port('myPortOut'), dst.port('myPortIn'));

      await top.build();
      final sv = top.generateSynth();
      // should compile, net name is auto-chosen
      expect(sv, isNotEmpty);

      src.output('myPortOut').put(0xA);
      expect(dst.input('myPortIn').value.toInt(), equals(0xA));
    });

    test('aligned slices: each half gets its own named net', () async {
      final top = BridgeModule('top');
      final mod1 = top.addSubModule(BridgeModule('mod1'));
      final mod2 = top.addSubModule(BridgeModule('mod2'));

      mod1.createPort('myPortOut', PortDirection.output, width: 32);
      mod2.createPort('myPortIn', PortDirection.input, width: 32);
      top.pullUpPort(mod1.createPort('dummy', PortDirection.output));

      connectPorts(mod1.port('myPortOut[15:0]'), mod2.port('myPortIn[15:0]'),
          intermediateSignalName: 'myPortOutLower');
      connectPorts(mod1.port('myPortOut[31:16]'), mod2.port('myPortIn[31:16]'),
          intermediateSignalName: 'myPortOutUpper');

      await top.build();
      final sv = top.generateSynth();

      // Both named nets exist and are 16 bits wide.
      expect(sv, matches(RegExp(r'logic\s*\[15:0\]\s*myPortOutLower')));
      expect(sv, matches(RegExp(r'logic\s*\[15:0\]\s*myPortOutUpper')));

      // Lower net driven by the low half, upper net by the high half.
      expect(sv, matches(RegExp(r'myPortOutLower\s*=\s*myPortOut\[15:0\]')));
      expect(sv, matches(RegExp(r'myPortOutUpper\s*=\s*myPortOut\[31:16\]')));

      // Verify all bits propagate correctly.
      mod1.output('myPortOut').put(0xDEADBEEF);
      expect(mod2.input('myPortIn').value.toInt(), equals(0xDEADBEEF));
    });

    test('driver slice into full receiver gets named net', () async {
      final (:top, :src, :dst) = _buildRig();

      src.createPort('myPortOut', PortDirection.output, width: 8);
      dst.createPort('myPortIn', PortDirection.input, width: 4);

      connectPorts(src.port('myPortOut[3:0]'), dst.port('myPortIn'),
          intermediateSignalName: 'lowNibble');

      await top.build();
      final sv = top.generateSynth();

      // 4-bit named net driven by the low nibble of myPortOut.
      expect(sv, matches(RegExp(r'logic\s*\[3:0\]\s*lowNibble')));
      expect(sv, matches(RegExp(r'lowNibble\s*=\s*myPortOut\[3:0\]')));
      expect(sv, matches(RegExp(r'\.myPortIn\s*\(\s*lowNibble\s*\)')));

      // Low nibble (0xB) of 0xAB should appear on myPortIn.
      src.output('myPortOut').put(0xAB);
      expect(dst.input('myPortIn').value.toInt(), equals(0xB));
    });

    test('sibling inOut ports: net appears by name in generated SV', () async {
      final top = BridgeModule('top');
      final modA = top.addSubModule(BridgeModule('modA'));
      final modB = top.addSubModule(BridgeModule('modB'));

      modA.createPort('portA', PortDirection.inOut, width: 4);
      modB.createPort('portB', PortDirection.inOut, width: 4);

      // pull the inOut up to top so it's traceable
      top.pullUpPort(modA.port('portA'));

      connectPorts(modA.port('portA'), modB.port('portB'),
          intermediateSignalName: 'inoutBus');

      await top.build();
      final sv = top.generateSynth();
      expect(sv, contains('inoutBus'));

      modA.port('portA').port.put(0xA);
      expect(modB.port('portB').port.value.toInt(), equals(0xA));
    });

    test('fan-out: multiple receivers share one named net', () async {
      final top = BridgeModule('top');
      final src = top.addSubModule(BridgeModule('src'));
      final dst1 = top.addSubModule(BridgeModule('dst1'));
      final dst2 = top.addSubModule(BridgeModule('dst2'));
      final dst3 = top.addSubModule(BridgeModule('dst3'));

      src.createPort('myPortOut', PortDirection.output);
      dst1.createPort('myPortIn_a', PortDirection.input);
      dst2.createPort('myPortIn_b', PortDirection.input);
      dst3.createPort('myPortIn_c', PortDirection.input);

      top
        ..pullUpPort(src.createPort('dummy', PortDirection.output))
        ..pullUpPort(dst1.createPort('dummy', PortDirection.output))
        ..pullUpPort(dst2.createPort('dummy', PortDirection.output))
        ..pullUpPort(dst3.createPort('dummy', PortDirection.output));

      // All three connections request the same net name from the same driver.
      connectPorts(src.port('myPortOut'), dst1.port('myPortIn_a'),
          intermediateSignalName: 'mySharedNet');
      connectPorts(src.port('myPortOut'), dst2.port('myPortIn_b'),
          intermediateSignalName: 'mySharedNet');
      connectPorts(src.port('myPortOut'), dst3.port('myPortIn_c'),
          intermediateSignalName: 'mySharedNet');

      await top.build();
      final sv = top.generateSynth();

      // Only one net declaration — not mySharedNet_0 or mySharedNet_1.
      expect(sv, contains('mySharedNet'));
      expect(sv, isNot(contains('mySharedNet_0')),
          reason: 'fan-out should reuse the same net, not uniquify');
      // All three inputs should be connected to mySharedNet in the portmaps.
      expect(sv, matches(RegExp(r'\.myPortIn_a\s*\(\s*mySharedNet\s*\)')));
      expect(sv, matches(RegExp(r'\.myPortIn_b\s*\(\s*mySharedNet\s*\)')));
      expect(sv, matches(RegExp(r'\.myPortIn_c\s*\(\s*mySharedNet\s*\)')));

      // All three receivers should see the driven value.
      src.output('myPortOut').put(1);
      expect(dst1.input('myPortIn_a').value.toInt(), equals(1));
      expect(dst2.input('myPortIn_b').value.toInt(), equals(1));
      expect(dst3.input('myPortIn_c').value.toInt(), equals(1));
    });

    test('nested fan-out reuses one named net', () async {
      final src = BridgeModule('src');
      final branch = BridgeModule('branch');
      final dst1 = branch.addSubModule(BridgeModule('dst1'));
      final dst2 = branch.addSubModule(BridgeModule('dst2'));

      src.createPort('myPortOut', PortDirection.output);
      dst1.createPort('myPortIn', PortDirection.input);
      dst2.createPort('myPortIn', PortDirection.input);

      final top = BridgeModule('top')
        ..addSubModule(src)
        ..addSubModule(branch)
        ..pullUpPort(src.createPort('dummy', PortDirection.output))
        ..pullUpPort(branch.pullUpPort(
            dst1.createPort('dummy', PortDirection.output),
            newPortName: 'dst1Dummy'))
        ..pullUpPort(branch.pullUpPort(
            dst2.createPort('dummy', PortDirection.output),
            newPortName: 'dst2Dummy'));

      connectPorts(src.port('myPortOut'), dst1.port('myPortIn'),
          intermediateSignalName: 'myNestedSharedNet');
      connectPorts(src.port('myPortOut'), dst2.port('myPortIn'),
          intermediateSignalName: 'myNestedSharedNet');

      await top.build();
      final sv = top.generateSynth();

      expect(sv, contains('myNestedSharedNet'));
      expect(sv, isNot(contains('myNestedSharedNet_0')));

      src.output('myPortOut').put(1);
      expect(dst1.input('myPortIn').value.toInt(), equals(1));
      expect(dst2.input('myPortIn').value.toInt(), equals(1));
    });

    test('fan-in: multiple inOut drivers share one named net', () async {
      final top = BridgeModule('top');
      final src1 = top.addSubModule(BridgeModule('src1'));
      final src2 = top.addSubModule(BridgeModule('src2'));
      final dst = top.addSubModule(BridgeModule('dst'));

      src1.createPort('bus1', PortDirection.inOut, width: 4);
      src2.createPort('bus2', PortDirection.inOut, width: 4);
      dst.createPort('busIn', PortDirection.inOut, width: 4);

      top
        ..pullUpPort(src1.createPort('dummy', PortDirection.output))
        ..pullUpPort(src2.createPort('dummy', PortDirection.output))
        ..pullUpPort(dst.createPort('dummy', PortDirection.output));

      connectPorts(src1.port('bus1'), dst.port('busIn'),
          intermediateSignalName: 'mySharedInOutNet');
      connectPorts(src2.port('bus2'), dst.port('busIn'),
          intermediateSignalName: 'mySharedInOutNet');

      await top.build();
      final sv = top.generateSynth();

      expect(sv, contains('mySharedInOutNet'));
      expect(sv, isNot(contains('mySharedInOutNet_0')));
      expect(sv, matches(RegExp(r'\.bus1\s*\(\s*mySharedInOutNet\s*\)')));
      expect(sv, matches(RegExp(r'\.bus2\s*\(\s*mySharedInOutNet\s*\)')));
      expect(sv, matches(RegExp(r'\.busIn\s*\(\s*mySharedInOutNet\s*\)')));
    });

    test('name collision auto-uniquifies (Naming.renameable)', () async {
      final top = BridgeModule('top');
      final src = top.addSubModule(BridgeModule('src'));
      final dst1 = top.addSubModule(BridgeModule('dst1'));
      final dst2 = top.addSubModule(BridgeModule('dst2'));

      src
        ..createPort('myPortOut1', PortDirection.output, width: 8)
        ..createPort('myPortOut2', PortDirection.output, width: 8);
      dst1.createPort('myPortIn', PortDirection.input, width: 8);
      dst2.createPort('myPortIn', PortDirection.input, width: 8);

      // dummy outputs for traceability
      top
        ..pullUpPort(src.createPort('dummy', PortDirection.output))
        ..pullUpPort(dst1.createPort('dummy', PortDirection.output))
        ..pullUpPort(dst2.createPort('dummy', PortDirection.output));

      // Both connections request the same net name; the second gets uniquified.
      connectPorts(src.port('myPortOut1'), dst1.port('myPortIn'),
          intermediateSignalName: 'mySharedNet');
      connectPorts(src.port('myPortOut2'), dst2.port('myPortIn'),
          intermediateSignalName: 'mySharedNet');

      await top.build();
      final sv = top.generateSynth();

      // The first connection should keep the base name; the second should be
      // uniquified to mySharedNet_0, mySharedNet_1, etc.
      expect(sv, contains('mySharedNet'),
          reason: 'at least one net should use the requested name');
      expect(sv, matches(RegExp(r'mySharedNet_\d+')),
          reason: 'second net with colliding name should be uniquified');

      // Each src should independently drive its intended dst.
      src.output('myPortOut1').put(0xAB);
      src.output('myPortOut2').put(0xCD);
      expect(dst1.input('myPortIn').value.toInt(), equals(0xAB));
      expect(dst2.input('myPortIn').value.toInt(), equals(0xCD));
    });

    test('vertical connection: intermediateSignalName is ignored (no-op)',
        () async {
      final grandParent = BridgeModule('grandParent');
      final parent = grandParent.addSubModule(BridgeModule('parent'));
      final child = parent.addSubModule(BridgeModule('child'))
        ..createPort('clk', PortDirection.input);

      grandParent.createPort('clk', PortDirection.input);

      // intermediateSignalName is silently ignored for non-sibling connections;
      // connectPorts handles the vertical punch-up as normal.
      // Should not throw, and signal should still propagate.
      connectPorts(grandParent.port('clk'), child.port('clk'),
          intermediateSignalName: 'clkRouted',
          allowIntermediateSignalNameUniquification: false);

      grandParent.input('clk').put(1);
      expect(child.input('clk').value.toInt(), equals(1));

      await grandParent.build();
    });
  });
}
