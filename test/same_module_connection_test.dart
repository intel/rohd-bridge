// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// same_module_connection_test.dart
// Tests for same-module connection disambiguation with
// SameModuleConnectionType.
//
// 2026 April
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
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
      for (final parentBeforeConnection in [false, true]) {
        for (final connectionType in SameModuleConnectionType.values) {
          final parentingState =
              parentBeforeConnection ? 'after parenting' : 'before parenting';

          test(
              'connects inOut ports with ${connectionType.name} '
              '$parentingState', () async {
            final mod = BridgeModule('testMod');
            final driver =
                mod.createPort('driver', PortDirection.inOut, width: 8);
            final receiver =
                mod.createPort('receiver', PortDirection.inOut, width: 8);
            final top = BridgeModule('top');

            if (parentBeforeConnection) {
              top.addSubModule(mod);
            }

            connectPorts(driver, receiver,
                sameModuleConnectionType: connectionType);

            if (!parentBeforeConnection) {
              top.addSubModule(mod);
            }
            top.pullUpPort(mod.createPort('dummyIn', PortDirection.input));

            await top.build();

            if (connectionType == SameModuleConnectionType.loopback) {
              expect(mod.inOutSource('receiver').srcConnections,
                  contains(mod.inOutSource('driver')));
            } else {
              expect(mod.inOut('receiver').srcConnections,
                  contains(mod.inOut('driver')));
            }
          });
        }
      }

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

    group('signal routing verification', () {
      test('inOut←inOut loopback routes through external ports', () async {
        final mod = BridgeModule('mod');
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        final driver = mod.createPort('driver', PortDirection.inOut, width: 8);
        mod.createPort('receiver', PortDirection.inOut, width: 8).gets(driver,
            sameModuleConnectionType: SameModuleConnectionType.loopback);
        await top.build();

        // External ports live on the parent module.
        final driverExternal = mod.inOutSource('driver');
        final receiverExternal = mod.inOutSource('receiver');
        expect(driverExternal.parentModule, equals(top));
        expect(receiverExternal.parentModule, equals(top));
        expect(receiverExternal.srcConnections, contains(driverExternal));

        // Internal path should NOT have a direct driver←driver connection.
        expect(mod.inOut('receiver').srcConnections,
            isNot(contains(mod.inOut('driver'))));
      });

      test('inOut←inOut passthrough routes through internal ports', () async {
        final mod = BridgeModule('mod');
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        final driver = mod.createPort('driver', PortDirection.inOut, width: 8);
        mod.createPort('receiver', PortDirection.inOut, width: 8).gets(driver,
            sameModuleConnectionType: SameModuleConnectionType.passthrough);
        await top.build();

        // Internal ports live on the module itself.
        final driverInternal = mod.inOut('driver');
        final receiverInternal = mod.inOut('receiver');
        expect(driverInternal.parentModule, equals(mod));
        expect(receiverInternal.parentModule, equals(mod));
        expect(receiverInternal.srcConnections, contains(driverInternal));

        // External path should NOT have the connection.
        expect(mod.inOutSource('receiver').srcConnections,
            isNot(contains(mod.inOutSource('driver'))));
      });

      test('inOut←output loopback routes through external ports', () async {
        final mod = BridgeModule('mod');
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        mod.createPort('driver', PortDirection.output, width: 8);
        mod.createPort('receiver', PortDirection.inOut, width: 8).gets(
            mod.port('driver'),
            sameModuleConnectionType: SameModuleConnectionType.loopback);
        await top.build();

        // Receiver external port lives on parent; driver output connects to it.
        final receiverExternal = mod.inOutSource('receiver');
        expect(receiverExternal.parentModule, equals(top));
        expect(receiverExternal.srcConnections, contains(mod.output('driver')));
      });

      test('inOut←output passthrough routes through internal ports', () async {
        final mod = BridgeModule('mod');
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        mod.createPort('driver', PortDirection.output, width: 8);
        mod.createPort('receiver', PortDirection.inOut, width: 8).gets(
            mod.port('driver'),
            sameModuleConnectionType: SameModuleConnectionType.passthrough);
        await top.build();

        // Internal receiver lives on mod; driver output connects to it.
        final receiverInternal = mod.inOut('receiver');
        expect(receiverInternal.parentModule, equals(mod));
        expect(receiverInternal.srcConnections, contains(mod.output('driver')));
      });

      test('output←inOut passthrough routes through internal ports', () async {
        final mod = BridgeModule('mod');
        final top = BridgeModule('top')
          ..addSubModule(mod)
          ..pullUpPort(mod.createPort('dummyIn', PortDirection.input));

        mod.createPort('driver', PortDirection.inOut, width: 8);
        mod.createPort('receiver', PortDirection.output, width: 8).gets(
            mod.port('driver'),
            sameModuleConnectionType: SameModuleConnectionType.passthrough);
        await top.build();

        // Output receiver is driven by the internal inOut port (on mod).
        final receiverOut = mod.output('receiver');
        final driverInternal = mod.inOut('driver');
        expect(receiverOut.parentModule, equals(mod));
        expect(driverInternal.parentModule, equals(mod));
        expect(receiverOut.srcConnection, equals(driverInternal));
      });
    });

    group('mapped interface ports', () {
      ({
        BridgeModule module,
        InterfaceReference intfRef,
        PortMap sourceMap,
        PortMap sinkMap,
      }) makeDeferredInterface() {
        final module = BridgeModule('leaf')
          ..addOutput('source_o')
          ..addInput('sink_i', null);
        final intfRef = module.addInterface(
          PairInterface(
            portsFromProvider: [Logic.port('source')],
            portsFromConsumer: [Logic.port('sink')],
          ),
          name: 'example',
          role: PairRole.provider,
          connect: false,
        );
        final sourceMap = module.addPortMap(
          module.port('source_o'),
          intfRef.port('source'),
        );
        final sinkMap = module.addPortMap(
          module.port('sink_i'),
          intfRef.port('sink'),
        );

        return (
          module: module,
          intfRef: intfRef,
          sourceMap: sourceMap,
          sinkMap: sinkMap,
        );
      }

      test('gets loopback activates deferred mappings', () {
        final fixture = makeDeferredInterface();
        final source = fixture.intfRef.port('source');
        fixture.intfRef.port('sink').gets(
              source,
              sameModuleConnectionType: SameModuleConnectionType.loopback,
            );

        expect(fixture.sourceMap.isConnected, isTrue);
        expect(fixture.sinkMap.isConnected, isTrue);
        expect(
          fixture.intfRef.interface.port('sink').srcConnection,
          fixture.intfRef.interface.port('source'),
        );
      });

      test('connectPorts loopback activates deferred mappings', () {
        final fixture = makeDeferredInterface();

        connectPorts(
          fixture.intfRef.port('source'),
          fixture.intfRef.port('sink'),
          sameModuleConnectionType: SameModuleConnectionType.loopback,
        );

        expect(fixture.sourceMap.isConnected, isTrue);
        expect(fixture.sinkMap.isConnected, isTrue);
      });

      test('gets passthrough routes through internal interface ports', () {
        final fixture = makeDeferredInterface();
        final source = fixture.intfRef.port('source');
        final sink = fixture.intfRef.port('sink');

        source.gets(
          sink,
          sameModuleConnectionType: SameModuleConnectionType.passthrough,
        );

        expect(fixture.sourceMap.isConnected, isTrue);
        expect(fixture.sinkMap.isConnected, isTrue);
        expect(
          fixture.intfRef.internalInterface!.port('source').srcConnection,
          fixture.intfRef.internalInterface!.port('sink'),
        );
      });

      test('preserves invalid connection type validation', () {
        final fixture = makeDeferredInterface();

        expect(
          () => fixture.intfRef.port('sink').gets(
                fixture.intfRef.port('source'),
                sameModuleConnectionType: SameModuleConnectionType.passthrough,
              ),
          throwsA(
            isA<RohdBridgeException>().having(
              (exception) => exception.message,
              'message',
              allOf(contains('not valid'), contains('loopback')),
            ),
          ),
        );
        expect(fixture.sourceMap.isConnected, isFalse);
        expect(fixture.sinkMap.isConnected, isFalse);
      });

      test('requires an explicit connection type', () {
        final fixture = makeDeferredInterface();

        expect(
          () =>
              fixture.intfRef.port('sink').gets(fixture.intfRef.port('source')),
          throwsA(
            isA<RohdBridgeException>().having(
              (exception) => exception.message,
              'message',
              allOf(
                contains('explicit'),
                contains('SameModuleConnectionType'),
              ),
            ),
          ),
        );
        expect(fixture.sourceMap.isConnected, isFalse);
        expect(fixture.sinkMap.isConnected, isFalse);
      });

      test('mixed passthrough uses internal interface and physical ports',
          () async {
        final module = BridgeModule('leaf')
          ..addInOut('bus_io', null)
          ..addInOut('peer_io', null);
        final intfRef = module.addInterface(
          PairInterface(commonInOutPorts: [LogicNet.port('bus')]),
          name: 'example',
          role: PairRole.provider,
          connect: false,
        );
        final portMap = module.addPortMap(
          module.port('bus_io'),
          intfRef.port('bus'),
        );
        final top = BridgeModule('top')
          ..addSubModule(module)
          ..pullUpPort(module.createPort('dummy', PortDirection.input));

        module.port('peer_io').gets(
              intfRef.port('bus'),
              sameModuleConnectionType: SameModuleConnectionType.passthrough,
            );

        expect(portMap.isConnected, isTrue);

        await top.build();

        expect(
          module.inOut('peer_io').srcConnections,
          contains(intfRef.internalInterface!.port('bus')),
        );
        expect(
          module.inOutSource('peer_io').srcConnections,
          isNot(contains(intfRef.interface.port('bus'))),
        );
      });

      test('mixed loopback uses external interface and physical ports',
          () async {
        final module = BridgeModule('leaf')
          ..addInOut('bus_io', null)
          ..addInOut('peer_io', null);
        final intfRef = module.addInterface(
          PairInterface(commonInOutPorts: [LogicNet.port('bus')]),
          name: 'example',
          role: PairRole.provider,
          connect: false,
        );
        final portMap = module.addPortMap(
          module.port('bus_io'),
          intfRef.port('bus'),
        );
        final top = BridgeModule('top')
          ..addSubModule(module)
          ..pullUpPort(module.createPort('dummy', PortDirection.input));

        module.port('peer_io').gets(
              intfRef.port('bus'),
              sameModuleConnectionType: SameModuleConnectionType.loopback,
            );

        expect(portMap.isConnected, isTrue);

        await top.build();

        expect(
          module.inOutSource('peer_io').srcConnections,
          contains(intfRef.interface.port('bus')),
        );
        expect(intfRef.internalInterface, isNull);
      });

      test('uses an existing mapping instead of directly reconnecting it', () {
        final fixture = makeDeferredInterface();
        fixture.intfRef.port('source').gets(fixture.module.port('source_o'));

        expect(fixture.sourceMap.isConnected, isTrue);
        expect(
          fixture.intfRef.interface.port('source').srcConnection,
          fixture.module.output('source_o'),
        );
      });

      test('supports exact sliced interface port mappings', () {
        final module = BridgeModule('leaf')
          ..addOutput('source_o', width: 4)
          ..addInput('sink_i', null, width: 4);
        final intfRef = module.addInterface(
          PairInterface(
            portsFromProvider: [Logic.port('source', 8)],
            portsFromConsumer: [Logic.port('sink', 8)],
          ),
          name: 'example',
          role: PairRole.provider,
          connect: false,
        );
        final sourceMap = module.addPortMap(
          module.port('source_o'),
          intfRef.port('source[3:0]'),
        );
        final sinkMap = module.addPortMap(
          module.port('sink_i'),
          intfRef.port('sink[3:0]'),
        );

        intfRef.port('sink[3:0]').gets(
              intfRef.port('source[3:0]'),
              sameModuleConnectionType: SameModuleConnectionType.loopback,
            );

        expect(sourceMap.isConnected, isTrue);
        expect(sinkMap.isConnected, isTrue);
      });

      test('rejects an unmapped interface port', () {
        final module = BridgeModule('leaf');
        final intfRef = module.addInterface(
          PairInterface(
            portsFromProvider: [Logic.port('source')],
            portsFromConsumer: [Logic.port('sink')],
          ),
          name: 'example',
          role: PairRole.provider,
          connect: false,
        );

        expect(
          () => intfRef.port('sink').gets(
                intfRef.port('source'),
                sameModuleConnectionType: SameModuleConnectionType.loopback,
              ),
          throwsA(
            isA<RohdBridgeException>().having(
              (exception) => exception.message,
              'message',
              contains('PortMap'),
            ),
          ),
        );
      });
    });
  });
}
