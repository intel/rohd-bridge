// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// same_module_connection_test.dart
// Tests for same-module connection disambiguation with
// SameModuleConnectionType.
//
// 2026 April
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

/// Describes one combination in the same-module connection matrix.
class _TestCase {
  final PortDirection receiverDir;
  final PortDirection driverDir;
  final SameModuleConnectionType? connectionType;
  final bool expectSuccess;

  const _TestCase({
    required this.receiverDir,
    required this.driverDir,
    required this.connectionType,
    required this.expectSuccess,
  });

  @override
  String toString() => '${receiverDir.name}←${driverDir.name}'
      ' (${connectionType?.name ?? 'null'}):'
      ' ${expectSuccess ? 'success' : 'fail'}';
}

/// All 27 test cases: 9 direction pairs × 3 enum values (null, loopback,
/// passthrough).
final _testCases = [
  // input←input: always fails
  for (final ct in _connectionTypes)
    _TestCase(
      receiverDir: PortDirection.input,
      driverDir: PortDirection.input,
      connectionType: ct,
      expectSuccess: false,
    ),

  // input←output: default=loopback, loopback=ok, passthrough=fail
  const _TestCase(
    receiverDir: PortDirection.input,
    driverDir: PortDirection.output,
    connectionType: null,
    expectSuccess: true,
  ),
  const _TestCase(
    receiverDir: PortDirection.input,
    driverDir: PortDirection.output,
    connectionType: SameModuleConnectionType.loopback,
    expectSuccess: true,
  ),
  const _TestCase(
    receiverDir: PortDirection.input,
    driverDir: PortDirection.output,
    connectionType: SameModuleConnectionType.passthrough,
    expectSuccess: false,
  ),

  // input←inOut: default=loopback, loopback=ok, passthrough=fail
  const _TestCase(
    receiverDir: PortDirection.input,
    driverDir: PortDirection.inOut,
    connectionType: null,
    expectSuccess: true,
  ),
  const _TestCase(
    receiverDir: PortDirection.input,
    driverDir: PortDirection.inOut,
    connectionType: SameModuleConnectionType.loopback,
    expectSuccess: true,
  ),
  const _TestCase(
    receiverDir: PortDirection.input,
    driverDir: PortDirection.inOut,
    connectionType: SameModuleConnectionType.passthrough,
    expectSuccess: false,
  ),

  // output←input: default=passthrough, loopback=fail, passthrough=ok
  const _TestCase(
    receiverDir: PortDirection.output,
    driverDir: PortDirection.input,
    connectionType: null,
    expectSuccess: true,
  ),
  const _TestCase(
    receiverDir: PortDirection.output,
    driverDir: PortDirection.input,
    connectionType: SameModuleConnectionType.loopback,
    expectSuccess: false,
  ),
  const _TestCase(
    receiverDir: PortDirection.output,
    driverDir: PortDirection.input,
    connectionType: SameModuleConnectionType.passthrough,
    expectSuccess: true,
  ),

  // output←output: equivalent, all succeed
  for (final ct in _connectionTypes)
    _TestCase(
      receiverDir: PortDirection.output,
      driverDir: PortDirection.output,
      connectionType: ct,
      expectSuccess: true,
    ),

  // output←inOut: AMBIGUOUS, null=fail, loopback=fail (build rejects
  // output driven by external inOut), passthrough=ok
  const _TestCase(
    receiverDir: PortDirection.output,
    driverDir: PortDirection.inOut,
    connectionType: null,
    expectSuccess: false,
  ),
  const _TestCase(
    receiverDir: PortDirection.output,
    driverDir: PortDirection.inOut,
    connectionType: SameModuleConnectionType.loopback,
    // ROHD build rejects output driven by inOutSource (external net)
    expectSuccess: false,
  ),
  const _TestCase(
    receiverDir: PortDirection.output,
    driverDir: PortDirection.inOut,
    connectionType: SameModuleConnectionType.passthrough,
    expectSuccess: true,
  ),

  // inOut←input: default=passthrough, loopback=fail, passthrough=ok
  const _TestCase(
    receiverDir: PortDirection.inOut,
    driverDir: PortDirection.input,
    connectionType: null,
    expectSuccess: true,
  ),
  const _TestCase(
    receiverDir: PortDirection.inOut,
    driverDir: PortDirection.input,
    connectionType: SameModuleConnectionType.loopback,
    expectSuccess: false,
  ),
  const _TestCase(
    receiverDir: PortDirection.inOut,
    driverDir: PortDirection.input,
    connectionType: SameModuleConnectionType.passthrough,
    expectSuccess: true,
  ),

  // inOut←output: AMBIGUOUS, null=fail, both enum values succeed
  const _TestCase(
    receiverDir: PortDirection.inOut,
    driverDir: PortDirection.output,
    connectionType: null,
    expectSuccess: false,
  ),
  const _TestCase(
    receiverDir: PortDirection.inOut,
    driverDir: PortDirection.output,
    connectionType: SameModuleConnectionType.loopback,
    expectSuccess: true,
  ),
  const _TestCase(
    receiverDir: PortDirection.inOut,
    driverDir: PortDirection.output,
    connectionType: SameModuleConnectionType.passthrough,
    expectSuccess: true,
  ),

  // inOut←inOut: AMBIGUOUS, null=fail, both enum values succeed
  const _TestCase(
    receiverDir: PortDirection.inOut,
    driverDir: PortDirection.inOut,
    connectionType: null,
    expectSuccess: false,
  ),
  const _TestCase(
    receiverDir: PortDirection.inOut,
    driverDir: PortDirection.inOut,
    connectionType: SameModuleConnectionType.loopback,
    expectSuccess: true,
  ),
  const _TestCase(
    receiverDir: PortDirection.inOut,
    driverDir: PortDirection.inOut,
    connectionType: SameModuleConnectionType.passthrough,
    expectSuccess: true,
  ),
];

const _connectionTypes = [
  null,
  SameModuleConnectionType.loopback,
  SameModuleConnectionType.passthrough,
];

void main() {
  group('same module connection type', () {
    group('gets()', () {
      for (final tc in _testCases) {
        test('gets: $tc', () async {
          final mod = BridgeModule('testMod');
          final top = BridgeModule('top')
            ..addSubModule(mod)
            ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

          final driverPort = mod.createPort('driver', tc.driverDir, width: 8);
          final receiverPort =
              mod.createPort('receiver', tc.receiverDir, width: 8);

          if (tc.expectSuccess) {
            receiverPort.gets(driverPort,
                sameModuleConnectionType: tc.connectionType);
            await top.build();
          } else {
            expect(
              () => receiverPort.gets(driverPort,
                  sameModuleConnectionType: tc.connectionType),
              throwsA(isA<RohdBridgeException>()),
            );
          }
        });
      }
    });

    group('connectPorts()', () {
      for (final tc in _testCases) {
        // connectPorts does hierarchy punching; for same-module it passes
        // through to gets().
        test('connectPorts: $tc', () async {
          final mod = BridgeModule('testMod');
          final top = BridgeModule('top')
            ..addSubModule(mod)
            ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

          final driverPort = mod.createPort('driver', tc.driverDir, width: 8);
          final receiverPort =
              mod.createPort('receiver', tc.receiverDir, width: 8);

          if (tc.expectSuccess) {
            connectPorts(driverPort, receiverPort,
                sameModuleConnectionType: tc.connectionType);
            await top.build();
          } else {
            expect(
              () => connectPorts(driverPort, receiverPort,
                  sameModuleConnectionType: tc.connectionType),
              throwsA(isA<RohdBridgeException>()),
            );
          }
        });
      }
    });

    group('sliced ports', () {
      for (final ct in [
        SameModuleConnectionType.loopback,
        SameModuleConnectionType.passthrough,
      ]) {
        test('inOut←inOut sliced with ${ct.name}', () async {
          final mod = BridgeModule('testMod');
          final top = BridgeModule('top')
            ..addSubModule(mod)
            ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

          final driverPort =
              mod.createPort('driver', PortDirection.inOut, width: 16);
          final receiverPort =
              mod.createPort('receiver', PortDirection.inOut, width: 16);

          receiverPort
              .slice(7, 0)
              .gets(driverPort.slice(7, 0), sameModuleConnectionType: ct);
          await top.build();
        });

        test('output←inOut sliced with ${ct.name}', () async {
          final mod = BridgeModule('testMod');
          final top = BridgeModule('top')
            ..addSubModule(mod)
            ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

          final driverPort =
              mod.createPort('driver', PortDirection.inOut, width: 16);
          final receiverPort =
              mod.createPort('receiver', PortDirection.output, width: 16);

          if (ct == SameModuleConnectionType.loopback) {
            // loopback is invalid for output←inOut
            expect(
              () => receiverPort
                  .slice(7, 0)
                  .gets(driverPort.slice(7, 0), sameModuleConnectionType: ct),
              throwsA(isA<RohdBridgeException>()),
            );
          } else {
            receiverPort
                .slice(7, 0)
                .gets(driverPort.slice(7, 0), sameModuleConnectionType: ct);
            await top.build();
          }
        });

        test('inOut←output sliced with ${ct.name}', () async {
          final mod = BridgeModule('testMod');
          final top = BridgeModule('top')
            ..addSubModule(mod)
            ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

          final driverPort =
              mod.createPort('driver', PortDirection.output, width: 16);
          final receiverPort =
              mod.createPort('receiver', PortDirection.inOut, width: 16);

          receiverPort
              .slice(7, 0)
              .gets(driverPort.slice(7, 0), sameModuleConnectionType: ct);
          await top.build();
        });
      }
    });

    group('non-same-module rejects enum', () {
      for (final ct in [
        SameModuleConnectionType.loopback,
        SameModuleConnectionType.passthrough,
      ]) {
        test('sibling modules with ${ct.name}', () {
          final modA = BridgeModule('modA');
          final modB = BridgeModule('modB');
          // top is only needed to establish hierarchy for gets() validation.
          // ignore: unused_local_variable
          final top = BridgeModule('top')
            ..addSubModule(modA)
            ..addSubModule(modB);

          final driverPort =
              modA.createPort('driver', PortDirection.output, width: 8);
          final receiverPort =
              modB.createPort('receiver', PortDirection.input, width: 8);

          expect(
            () => connectPorts(driverPort, receiverPort,
                sameModuleConnectionType: ct),
            throwsA(isA<RohdBridgeException>()),
          );
        });
      }

      test('gives helpful message', () {
        final modA = BridgeModule('modA');
        final modB = BridgeModule('modB');
        // top is only needed to establish hierarchy for gets() validation.
        // ignore: unused_local_variable
        final top = BridgeModule('top')
          ..addSubModule(modA)
          ..addSubModule(modB);

        final driverPort =
            modA.createPort('driver', PortDirection.output, width: 8);
        final receiverPort =
            modB.createPort('receiver', PortDirection.input, width: 8);

        expect(
          () => connectPorts(driverPort, receiverPort,
              sameModuleConnectionType: SameModuleConnectionType.loopback),
          throwsA(
            isA<RohdBridgeException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('only be provided'),
                contains('same module'),
              ),
            ),
          ),
        );
      });
    });

    group('error messages', () {
      test('ambiguous inOut←inOut gives helpful message', () {
        final mod = BridgeModule('testMod');
        // top is only needed to establish hierarchy for gets() validation.
        // ignore: unused_local_variable
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        final driver = mod.createPort('d', PortDirection.inOut, width: 8);
        final receiver = mod.createPort('r', PortDirection.inOut, width: 8);

        expect(
          () => receiver.gets(driver),
          throwsA(
            isA<RohdBridgeException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('ambiguous'),
                contains('SameModuleConnectionType'),
              ),
            ),
          ),
        );
      });

      test('ambiguous output←inOut gives helpful message', () {
        final mod = BridgeModule('testMod');
        // top is only needed to establish hierarchy for gets() validation.
        // ignore: unused_local_variable
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        final driver = mod.createPort('d', PortDirection.inOut, width: 8);
        final receiver = mod.createPort('r', PortDirection.output, width: 8);

        expect(
          () => receiver.gets(driver),
          throwsA(
            isA<RohdBridgeException>().having(
              (e) => e.message,
              'message',
              contains('ambiguous'),
            ),
          ),
        );
      });

      test('ambiguous inOut←output gives helpful message', () {
        final mod = BridgeModule('testMod');
        // top is only needed to establish hierarchy for gets() validation.
        // ignore: unused_local_variable
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        final driver = mod.createPort('d', PortDirection.output, width: 8);
        final receiver = mod.createPort('r', PortDirection.inOut, width: 8);

        expect(
          () => receiver.gets(driver),
          throwsA(
            isA<RohdBridgeException>().having(
              (e) => e.message,
              'message',
              contains('ambiguous'),
            ),
          ),
        );
      });

      test('wrong type for input←output gives helpful message', () {
        final mod = BridgeModule('testMod');
        // top is only needed to establish hierarchy for gets() validation.
        // ignore: unused_local_variable
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        final driver = mod.createPort('d', PortDirection.output, width: 8);
        final receiver = mod.createPort('r', PortDirection.input, width: 8);

        expect(
          () => receiver.gets(driver,
              sameModuleConnectionType: SameModuleConnectionType.passthrough),
          throwsA(
            isA<RohdBridgeException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('not valid'),
                contains('loopback'),
              ),
            ),
          ),
        );
      });

      test('wrong type for output←input gives helpful message', () {
        final mod = BridgeModule('testMod');
        // top is only needed to establish hierarchy for gets() validation.
        // ignore: unused_local_variable
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        final driver = mod.createPort('d', PortDirection.input, width: 8);
        final receiver = mod.createPort('r', PortDirection.output, width: 8);

        expect(
          () => receiver.gets(driver,
              sameModuleConnectionType: SameModuleConnectionType.loopback),
          throwsA(
            isA<RohdBridgeException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('not valid'),
                contains('passthrough'),
              ),
            ),
          ),
        );
      });

      test('loopback invalid for output←inOut gives helpful message', () {
        final mod = BridgeModule('testMod');
        // top is only needed to establish hierarchy for gets() validation.
        // ignore: unused_local_variable
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        final driver = mod.createPort('d', PortDirection.inOut, width: 8);
        final receiver = mod.createPort('r', PortDirection.output, width: 8);

        expect(
          () => receiver.gets(driver,
              sameModuleConnectionType: SameModuleConnectionType.loopback),
          throwsA(
            isA<RohdBridgeException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('not valid'),
                contains('passthrough'),
              ),
            ),
          ),
        );
      });
    });
  });
}
