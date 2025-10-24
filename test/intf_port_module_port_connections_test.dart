// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// intf_port_module_port_connections_test.dart
// Unit tests for connections between ports and intf ports.
//
// 2025 September 29
// Author: Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/src/bridge_module.dart';
import 'package:rohd_bridge/src/port_direction.dart';
import 'package:rohd_bridge/src/references/references.dart';
import 'package:rohd_bridge/src/rohd_bridge_exception.dart';
import 'package:test/test.dart';

class _PortTestCase {
  final bool isIntfPort;
  final PortDirection direction;

  // For testing purposes, it's ok positional here.
  // ignore: avoid_positional_boolean_parameters
  const _PortTestCase(this.isIntfPort, this.direction);

  @override
  String toString() => '${direction.name} ${isIntfPort ? 'intf port' : 'port'}';
}

enum _RelativePosition {
  srcAboveDst,
  dstAboveSrc,
  sameLevel,
  sameModule;
}

class _PortConnectionTestCase {
  final _PortTestCase src;
  final _PortTestCase dst;
  final _RelativePosition relativePosition;

  const _PortConnectionTestCase(this.src, this.dst, this.relativePosition);

  @override
  String toString() => '${relativePosition.name}  $src -> $dst ';
}

class TestIntf extends PairInterface {
  final bool isIo;
  final int width;
  TestIntf({required this.isIo, required this.width})
      : super(portsFromProvider: [
          if (!isIo) Logic.port('testPort', width),
        ], commonInOutPorts: [
          if (isIo) LogicNet.port('testPort', width)
        ]);

  @override
  TestIntf clone() => TestIntf(isIo: isIo, width: width);
}

void main() {
  group('port intf port connections', () {
    final portTestCases = [
      for (final isIntfPort in [true, false])
        for (final direction in PortDirection.values)
          _PortTestCase(isIntfPort, direction)
    ];

    final portConnectionTestCases = [
      for (final src in portTestCases)
        for (final dst in portTestCases)
          for (final relativePos in _RelativePosition.values)
            if ((src.direction == PortDirection.inOut) ==
                (dst.direction == PortDirection.inOut))
              _PortConnectionTestCase(src, dst, relativePos)
    ];

    final connectApis = [
      ('connectPorts', connectPorts),
      ('gets', (PortReference src, PortReference dst) => dst.gets(src)),
    ];

    for (final withPortSlicing in [false, true]) {
      for (final withIntfPortSlicing in [false, true]) {
        group(withIntfPortSlicing ? 'sliced intf port' : 'standard intf port',
            () {
          group(withPortSlicing ? 'sliced port' : 'standard port', () {
            for (final connectApi in connectApis) {
              final connectName = connectApi.$1;
              final connectFunc = connectApi.$2;

              group('using $connectName', () {
                for (final testCase in portConnectionTestCases) {
                  test(testCase.toString(), () async {
                    final srcMod = BridgeModule('modA');

                    final dstMod = testCase.relativePosition ==
                            _RelativePosition.sameModule
                        ? srcMod
                        : BridgeModule('modB');

                    final top = BridgeModule('top');

                    switch (testCase.relativePosition) {
                      case _RelativePosition.srcAboveDst:
                        srcMod.addSubModule(dstMod);
                        top.addSubModule(srcMod);
                      case _RelativePosition.dstAboveSrc:
                        dstMod.addSubModule(srcMod);
                        top.addSubModule(dstMod);
                      case _RelativePosition.sameLevel:
                        top.addSubModule(srcMod);
                        top.addSubModule(dstMod);
                      case _RelativePosition.sameModule:
                        top.addSubModule(srcMod);
                    }

                    top
                      ..pullUpPort(
                          srcMod.createPort('dummyIn', PortDirection.input))
                      ..pullUpPort(
                          dstMod.createPort('dummyOut', PortDirection.output));

                    final rawPortWidth = withPortSlicing ? 16 : 8;
                    final rawIntfPortWidth = withIntfPortSlicing ? 16 : 8;

                    final srcPort = srcMod.createPort(
                        'src', testCase.src.direction,
                        width: rawPortWidth);
                    final dstPort = dstMod.createPort(
                        'dst', testCase.dst.direction,
                        width: rawPortWidth);

                    var srcPortRef = srcPort;
                    var dstPortRef = dstPort;

                    if (withPortSlicing) {
                      srcPortRef = srcPortRef.slice(7, 0);
                      dstPortRef = dstPortRef.slice(7, 0);
                    }

                    var expectFailure = false;

                    if ((testCase.src.isIntfPort || testCase.dst.isIntfPort) &&
                        testCase.relativePosition ==
                            _RelativePosition.sameModule) {
                      // cannot have intf port connection on same module, must
                      // be a port map
                      expectFailure = true;
                    }

                    if (testCase.relativePosition ==
                            _RelativePosition.sameLevel &&
                        testCase.src.direction == testCase.dst.direction &&
                        testCase.src.direction != PortDirection.inOut) {
                      // this is like a pass-through, not yet supported
                      expectFailure = true;
                    }

                    if (testCase.relativePosition ==
                            _RelativePosition.dstAboveSrc &&
                        testCase.src.direction == PortDirection.input &&
                        testCase.dst.direction == PortDirection.input) {
                      // child input cannot drive parent input
                      expectFailure = true;
                    }

                    if (testCase.relativePosition ==
                            _RelativePosition.srcAboveDst &&
                        testCase.src.direction == PortDirection.output &&
                        testCase.dst.direction == PortDirection.output) {
                      // parent output cannot drive child output
                      expectFailure = true;
                    }

                    if ((testCase.relativePosition ==
                                _RelativePosition.srcAboveDst ||
                            testCase.relativePosition ==
                                _RelativePosition.dstAboveSrc) &&
                        (testCase.src.direction != testCase.dst.direction)) {
                      // vertical connections should have the same direction
                      expectFailure = true;
                    }

                    if (testCase.relativePosition ==
                            _RelativePosition.sameLevel &&
                        testCase.src.direction == PortDirection.input &&
                        testCase.dst.direction == PortDirection.output) {
                      // input cannot drive output at same level
                      expectFailure = true;
                    }

                    if (testCase.relativePosition ==
                            _RelativePosition.sameModule &&
                        testCase.dst.direction == PortDirection.input &&
                        testCase.src.direction == PortDirection.input) {
                      // port cant drive input on same module
                      expectFailure = true;
                    }

                    try {
                      if (testCase.src.isIntfPort) {
                        final srcIntf = srcMod.addInterface(
                            TestIntf(
                                isIo: testCase.src.direction ==
                                    PortDirection.inOut,
                                width: rawIntfPortWidth),
                            name: 'testIntfA',
                            role: srcPort.direction == PortDirection.input
                                ? PairRole.consumer
                                : PairRole.provider,
                            connect: false);

                        srcMod.addPortMap(
                            srcPortRef, srcIntf.port('testPort').slice(7, 0),
                            connect: true);

                        srcPortRef = srcIntf.port('testPort').slice(7, 0);
                      }

                      if (testCase.dst.isIntfPort) {
                        final dstIntf = dstMod.addInterface(
                            TestIntf(
                                isIo: testCase.dst.direction ==
                                    PortDirection.inOut,
                                width: rawIntfPortWidth),
                            name: 'testIntfB',
                            role: dstPort.direction == PortDirection.output
                                ? PairRole.provider
                                : PairRole.consumer,
                            connect: false);

                        dstMod.addPortMap(
                            dstPortRef, dstIntf.port('testPort').slice(7, 0),
                            connect: true);

                        dstPortRef = dstIntf.port('testPort').slice(7, 0);
                      }

                      connectFunc(srcPortRef, dstPortRef);

                      await top.build();

                      final val = LogicValue.of(0x45, width: 8);
                      srcPort.port.put(val);
                      expect(dstPort.port.value.slice(7, 0), equals(val));

                      if (expectFailure) {
                        fail('Expected failure but connection succeeded');
                      }
                    } on RohdBridgeException catch (e) {
                      // we only catch RohdBridgeException! make sure we have
                      // good error messages!

                      if (!expectFailure) {
                        fail('Unexpected failure: $e');
                      }
                    }
                  });
                }
              });
            }
          });
        });
      }
    }
  });
}
