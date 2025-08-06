// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// connection_extractor_test.dart
// Tests for the connection extractor.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

import 'intf_hier_conn_test.dart';

class MyNetIntf extends PairInterface {
  MyNetIntf()
      : super(
          commonInOutPorts: [LogicNet.port('myInOut', 3)],
        );

  @override
  MyNetIntf clone() => MyNetIntf();
}

void main() {
  test('simple port to port same hierarchy', () async {
    final sub1 = BridgeModule('sub1')
      ..createPort('mySrc', PortDirection.output)
      ..createPort('clk', PortDirection.input);
    final sub2 = BridgeModule('sub2')..createPort('myDst', PortDirection.input);
    final top = BridgeModule('top')
      ..addSubModule(sub1)
      ..addSubModule(sub2);

    // to make modules discoverable
    sub1.port('clk').punchUpTo(top);

    // make a connection
    connectPorts(
      sub1.port('mySrc'),
      sub2.port('myDst'),
    );

    await top.build();

    final extractor = ConnectionExtractor(top.subBridgeModules);

    expect(extractor.connections.length, 1);
    expect(extractor.connections.first, isA<AdHocConnection>());
    final connection = extractor.connections.first as AdHocConnection;
    expect(connection.src.portName, 'mySrc');
    expect(connection.dst.portName, 'myDst');
  });

  test('simple intf to intf same hierarchy', () async {
    final sub1 = BridgeModule('sub1')
      ..addInterface(MyIntf(), name: 'i1', role: PairRole.provider)
      ..createPort('clk', PortDirection.input);
    final sub2 = BridgeModule('sub2')
      ..addInterface(MyIntf(), name: 'i2', role: PairRole.consumer);
    final top = BridgeModule('top')
      ..addSubModule(sub1)
      ..addSubModule(sub2);

    // to make modules discoverable
    sub1.port('clk').punchUpTo(top);

    // make a connection
    connectInterfaces(
      sub1.interface('i1'),
      sub2.interface('i2'),
    );

    await top.build();

    final extractor = ConnectionExtractor(top.subBridgeModules);

    expect(extractor.connections.length, 1);
    expect(extractor.connections.first, isA<InterfaceConnection>());
    final connection = extractor.connections.first as InterfaceConnection;
    expect(connection.point1.name, 'i1');
    expect(connection.point2.name, 'i2');
  });

  test('simple both intf and ad hoc same hierarchy', () async {
    final sub1 = BridgeModule('sub1')
      ..createPort('mySrc', PortDirection.output)
      ..addInterface(MyIntf(), name: 'i1', role: PairRole.provider)
      ..createPort('clk', PortDirection.input);
    final sub2 = BridgeModule('sub2')
      ..createPort('myDst', PortDirection.input)
      ..addInterface(MyIntf(), name: 'i2', role: PairRole.consumer);
    final top = BridgeModule('top')
      ..addSubModule(sub1)
      ..addSubModule(sub2);

    // to make modules discoverable
    sub1.port('clk').punchUpTo(top);

    // make an adHoc connection
    connectPorts(
      sub1.port('mySrc'),
      sub2.port('myDst'),
    );

    // make an intf connection
    connectInterfaces(
      sub1.interface('i1'),
      sub2.interface('i2'),
    );

    await top.build();

    final extractor = ConnectionExtractor(top.subBridgeModules);

    final adHocConnections =
        extractor.connections.whereType<AdHocConnection>().toList();
    final intfConnections =
        extractor.connections.whereType<InterfaceConnection>().toList();
    expect(adHocConnections.length, 1);
    expect(intfConnections.length, 1);
    expect(adHocConnections.first.src.portName, 'mySrc');
    expect(adHocConnections.first.dst.portName, 'myDst');
    expect(intfConnections.first.point1.name, 'i1');
    expect(intfConnections.first.point2.name, 'i2');
    expect(extractor.connections.length, 2);
  });

  test('slice of interface port does not show as full intf connection',
      () async {
    final sub1 = BridgeModule('sub1')
      ..addInterface(MyIntf(), name: 'i1', role: PairRole.provider)
      ..createPort('clk', PortDirection.input);
    final sub2 = BridgeModule('sub2')
      ..addInterface(MyIntf(), name: 'i2', role: PairRole.consumer);
    final top = BridgeModule('top')
      ..addSubModule(sub1)
      ..addSubModule(sub2);

    // to make modules discoverable
    sub1.port('clk').punchUpTo(top);

    // make a connection
    connectPorts(
      sub1.interface('i1').port('myProviderPort').slice(4, 1),
      sub2.interface('i2').port('myProviderPort').slice(4, 1),
    );
    connectPorts(
      sub2.interface('i2').port('myConsumerPort'),
      sub1.interface('i1').port('myConsumerPort'),
    );

    await top.build();

    final extractor = ConnectionExtractor(top.subBridgeModules);

    expect(extractor.connections.whereType<InterfaceConnection>(), isEmpty);
    expect(extractor.connections.whereType<AdHocConnection>().length, 5);

    // Expect connections for each bit of the sliced provider port
    for (var i = 1; i <= 4; i++) {
      expect(
        extractor.connections,
        contains(AdHocConnection(
          sub1.port('i1_myProviderPort')[i],
          sub2.port('i2_myProviderPort')[i],
        )),
      );
    }
    // Expect connection for the full consumer port
    expect(
      extractor.connections,
      contains(AdHocConnection(
        sub2.port('i2_myConsumerPort'),
        sub1.port('i1_myConsumerPort'),
      )),
    );
  });

  group('multi-module testing', () {
    test('>2 modules in same hierarchy', () async {
      final sub1 = BridgeModule('sub1')
        ..createPort('mySrc', PortDirection.output, width: 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createPort('myDst', PortDirection.input, width: 8)
        ..createPort('myFeedThrough', PortDirection.output, width: 8);
      final sub3 = BridgeModule('sub3')
        ..createPort('myFinalDst', PortDirection.input, width: 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2)
        ..addSubModule(sub3);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make connections
      connectPorts(
        sub1.port('mySrc'),
        sub2.port('myDst'),
      );
      connectPorts(
        sub2.port('myFeedThrough'),
        sub3.port('myFinalDst'),
      );

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 2);
      final expectedConnections = [
        AdHocConnection(
          sub1.port('mySrc'),
          sub2.port('myDst'),
        ),
        AdHocConnection(
          sub2.port('myFeedThrough'),
          sub3.port('myFinalDst'),
        ),
      ];
      for (final connection in expectedConnections) {
        expect(extractor.connections, contains(connection));
      }
    });

    test('stack of three modules', () async {
      final leaf = BridgeModule('leaf')
        ..createPort('mySrc', PortDirection.output, width: 8);
      final mid = BridgeModule('mid')..addSubModule(leaf);
      final top = BridgeModule('top')..addSubModule(mid);

      leaf.port('mySrc').punchUpTo(top, newPortName: 'mySrc');

      await top.build();

      final extractor = ConnectionExtractor([top, mid, leaf]);

      final expectedConnections = [
        AdHocConnection(
          leaf.port('mySrc'),
          mid.port('mySrc'),
        ),
        AdHocConnection(
          mid.port('mySrc'),
          top.port('mySrc'),
        ),
      ];

      expect(extractor.connections.length, 2);
      for (final connection in expectedConnections) {
        expect(extractor.connections, contains(connection));
      }
    });
  });

  test('slice src to full dst port to port same hierarchy', () async {
    final sub1 = BridgeModule('sub1')
      ..createPort('mySrc', PortDirection.output, width: 16)
      ..createPort('clk', PortDirection.input);
    final sub2 = BridgeModule('sub2')
      ..createPort('myDst', PortDirection.input, width: 8);
    final top = BridgeModule('top')
      ..addSubModule(sub1)
      ..addSubModule(sub2);

    // to make modules discoverable
    sub1.port('clk').punchUpTo(top);

    // make a connection
    connectPorts(
      sub1.port('mySrc[8:1]'),
      sub2.port('myDst'),
    );

    final extractor = ConnectionExtractor(top.subBridgeModules);

    expect(extractor.connections.length, 1);
    expect(extractor.connections.first, isA<AdHocConnection>());
    final connection = extractor.connections.first as AdHocConnection;
    expect(connection.src.portName, 'mySrc');
    expect(connection.dst.portName, 'myDst');
    expect(connection.src, isA<SlicePortReference>());
    final sliceSrcRef = connection.src as SlicePortReference;
    expect(sliceSrcRef.sliceLowerIndex, 1);
    expect(sliceSrcRef.sliceUpperIndex, 8);
    expect(sliceSrcRef.width, 8);
    expect(connection.dst is SlicePortReference, isFalse);
    expect(connection.dst.width, 8);
  });

  test('full src to slice dst port to port same hierarchy', () async {
    final sub1 = BridgeModule('sub1')
      ..createPort('mySrc', PortDirection.output, width: 8)
      ..createPort('clk', PortDirection.input);
    final sub2 = BridgeModule('sub2')
      ..createPort('myDst', PortDirection.input, width: 16);
    final top = BridgeModule('top')
      ..addSubModule(sub1)
      ..addSubModule(sub2);

    // to make modules discoverable
    sub1.port('clk').punchUpTo(top);

    // make a connection
    connectPorts(
      sub1.port('mySrc'),
      sub2.port('myDst[8:1]'),
    );

    await top.build();

    final extractor = ConnectionExtractor(top.subBridgeModules);

    expect(extractor.connections.length, 8);
    expect(extractor.connections.every((e) => e is AdHocConnection), isTrue);
    for (var i = 0; i < 8; i++) {
      expect(
          extractor.connections,
          contains(AdHocConnection(
            sub1.port('mySrc[$i]'),
            sub2.port('myDst[${i + 1}]'),
          )));
    }
  });

  test('slice to slice port same hierarchy', () async {
    final sub1 = BridgeModule('sub1')
      ..createPort('mySrc', PortDirection.output, width: 8)
      ..createPort('clk', PortDirection.input);
    final sub2 = BridgeModule('sub2')
      ..createPort('myDst', PortDirection.input, width: 8);
    final top = BridgeModule('top')
      ..addSubModule(sub1)
      ..addSubModule(sub2);

    // to make modules discoverable
    sub1.port('clk').punchUpTo(top);

    // make a connection
    connectPorts(
      sub1.port('mySrc[2:1]'),
      sub2.port('myDst[7:6]'),
    );

    await top.build();

    final extractor = ConnectionExtractor(top.subBridgeModules);

    expect(extractor.connections.length, 2);
    expect(extractor.connections.every((e) => e is AdHocConnection), isTrue);
    for (var i = 0; i < 2; i++) {
      expect(
          extractor.connections,
          contains(AdHocConnection(
            sub1.port('mySrc[${i + 1}]'),
            sub2.port('myDst[${i + 6}]'),
          )));
    }
  });

  test('multi-full swizzled to full same hierarchy', () async {
    final sub1 = BridgeModule('sub1')
      ..createPort('mySrc1', PortDirection.output, width: 8)
      ..createPort('mySrc2', PortDirection.output, width: 8)
      ..createPort('clk', PortDirection.input);
    final sub2 = BridgeModule('sub2')
      ..createPort('myDst', PortDirection.input, width: 16);
    final top = BridgeModule('top')
      ..addSubModule(sub1)
      ..addSubModule(sub2);

    // to make modules discoverable
    sub1.port('clk').punchUpTo(top);

    // make a connection
    connectPorts(
      sub1.port('mySrc1'),
      sub2.port('myDst[7:0]'),
    );
    connectPorts(
      sub1.port('mySrc2'),
      sub2.port('myDst[15:8]'),
    );

    await top.build();

    final extractor = ConnectionExtractor(top.subBridgeModules);

    expect(extractor.connections.length, 16);
    expect(extractor.connections.every((e) => e is AdHocConnection), isTrue);
    for (var i = 0; i < 16; i++) {
      expect(
          extractor.connections,
          contains(AdHocConnection(
            sub1.port('mySrc${i ~/ 8 + 1}[${i % 8}]'),
            sub2.port('myDst[$i]'),
          )));
    }
  });

  test('multi-level slicing', () async {
    final sub1 = BridgeModule('sub1')
      ..createPort('mySrc', PortDirection.output, width: 64)
      ..createPort('clk', PortDirection.input);
    final mid1 = BridgeModule('mid1')
      ..createPort('mid1src', PortDirection.output, width: 32)
      ..addSubModule(sub1);
    final sub2 = BridgeModule('sub2')
      ..createPort('myDst', PortDirection.input, width: 8);
    final mid2 = BridgeModule('mid2')
      ..createPort('mid2dst', PortDirection.input, width: 16)
      ..addSubModule(sub2);
    final top = BridgeModule('top')
      ..addSubModule(mid1)
      ..addSubModule(mid2);

    // to make modules discoverable
    sub1.port('clk').punchUpTo(top);

    // make a connection
    connectPorts(
      sub1.port('mySrc[15:0]'),
      mid1.port('mid1src[15:0]'),
    );
    connectPorts(
      sub1.port('mySrc[63:48]'),
      mid1.port('mid1src[31:16]'),
    );

    connectPorts(
      mid1.port('mid1src[31:24]'),
      mid2.port('mid2dst[7:0]'),
    );
    connectPorts(
      mid1.port('mid1src[7:0]'),
      mid2.port('mid2dst[15:8]'),
    );

    connectPorts(
      mid2.port('mid2dst[3:0]'),
      sub2.port('myDst[3:0]'),
    );
    connectPorts(
      mid2.port('mid2dst[15:12]'),
      sub2.port('myDst[7:4]'),
    );

    await top.build();

    final extractor = ConnectionExtractor([sub1, sub2]);

    final mySrc = sub1.port('mySrc');
    final myDst = sub2.port('myDst');
    for (final connection in extractor.connections) {
      expect(connection, isA<AdHocConnection>());
      final adHocConnection = connection as AdHocConnection;
      expect(adHocConnection.src.width, 1);
      expect(adHocConnection.dst.width, 1);

      final srcIdx =
          (adHocConnection.src as SlicePortReference).dimensionAccess!.last;
      final dstIdx =
          (adHocConnection.dst as SlicePortReference).dimensionAccess!.last;
      mySrc.port.put(BigInt.one << srcIdx);

      for (var d = 0; d < myDst.width; d++) {
        final expectedValue = d == dstIdx ? LogicValue.one : null;
        expect(
            d == dstIdx
                ? myDst.port.value[d].toBool()
                : [LogicValue.zero, LogicValue.z].contains(myDst.port.value[d]),
            isTrue,
            reason: 'Expected $srcIdx of $mySrc '
                'to connect to $dstIdx of $myDst only. '
                'Saw mismatch at dest index $d (expected $expectedValue)');
      }
    }
  });

  group('array stuff', () {
    test('array element to normal', () async {
      final sub1 = BridgeModule('sub1')
        ..createArrayPort('mySrc', PortDirection.output,
            dimensions: [4, 3], elementWidth: 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createPort('myDst', PortDirection.input, width: 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      final src = sub1.port('mySrc[2][1]');
      final dst = sub2.port('myDst');
      connectPorts(src, dst);

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 1);
      expect(extractor.connections.first, isA<AdHocConnection>());
      final connection = extractor.connections.first as AdHocConnection;
      expect(connection, AdHocConnection(src, dst));
    });

    test('normal to array element', () async {
      final sub1 = BridgeModule('sub1')
        ..createPort('mySrc', PortDirection.output, width: 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createArrayPort('myDst', PortDirection.input,
            dimensions: [4, 3], elementWidth: 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      final src = sub1.port('mySrc');
      final dst = sub2.port('myDst[2][1]');
      connectPorts(src, dst);

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 1);
      expect(extractor.connections.first, isA<AdHocConnection>());
      final connection = extractor.connections.first as AdHocConnection;
      expect(connection, AdHocConnection(src, dst));
    });

    test('array element to array element', () async {
      final sub1 = BridgeModule('sub1')
        ..createArrayPort('mySrc', PortDirection.output,
            dimensions: [4, 3], elementWidth: 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createArrayPort('myDst', PortDirection.input,
            dimensions: [5, 4], elementWidth: 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      final src = sub1.port('mySrc[2][1]');
      final dst = sub2.port('myDst[3][2]');
      connectPorts(src, dst);

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 1);
      expect(extractor.connections.first, isA<AdHocConnection>());
      final connection = extractor.connections.first as AdHocConnection;
      expect(connection, AdHocConnection(src, dst));
    });

    test('array element slice to array element slice', () async {
      final sub1 = BridgeModule('sub1')
        ..createArrayPort('mySrc', PortDirection.output,
            dimensions: [4, 3], elementWidth: 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createArrayPort('myDst', PortDirection.input,
            dimensions: [5, 4], elementWidth: 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      final src = sub1.port('mySrc[2][1][4:2]');
      final dst = sub2.port('myDst[3][2][3:1]');
      connectPorts(src, dst);

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 3);

      final expectedConnections = [
        AdHocConnection(
          sub1.port('mySrc[2][1][4]'),
          sub2.port('myDst[3][2][3]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[2][1][3]'),
          sub2.port('myDst[3][2][2]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[2][1][2]'),
          sub2.port('myDst[3][2][1]'),
        ),
      ];

      for (final expectedConnection in expectedConnections) {
        expect(extractor.connections, contains(expectedConnection));
      }
    });

    test('sub-array to sub-array', () async {
      final sub1 = BridgeModule('sub1')
        ..createArrayPort('mySrc', PortDirection.output,
            dimensions: [4, 3], elementWidth: 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createArrayPort('myDst', PortDirection.input,
            dimensions: [5, 3], elementWidth: 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      final src = sub1.port('mySrc[2]');
      final dst = sub2.port('myDst[3]');
      connectPorts(src, dst);

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 3);

      final expectedConnections = [
        AdHocConnection(
          sub1.port('mySrc[2][0]'),
          sub2.port('myDst[3][0]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[2][1]'),
          sub2.port('myDst[3][1]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[2][2]'),
          sub2.port('myDst[3][2]'),
        ),
      ];

      for (final expectedConnection in expectedConnections) {
        expect(extractor.connections, contains(expectedConnection));
      }
    });

    test('packed array to normal', () async {
      final sub1 = BridgeModule('sub1')
        ..createArrayPort('mySrc', PortDirection.output,
            dimensions: [3, 2], elementWidth: 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createPort('myDst', PortDirection.input, width: 3 * 2 * 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      final src = sub1.port('mySrc');
      final dst = sub2.port('myDst');
      connectPorts(src, dst);

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      final expectedConnections = <AdHocConnection>[
        AdHocConnection(
          sub1.port('mySrc[0][0]'),
          sub2.port('myDst[7:0]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[0][1]'),
          sub2.port('myDst[15:8]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[1][0]'),
          sub2.port('myDst[23:16]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[1][1]'),
          sub2.port('myDst[31:24]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[2][0]'),
          sub2.port('myDst[39:32]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[2][1]'),
          sub2.port('myDst[47:40]'),
        ),
      ];

      expect(extractor.connections.length, expectedConnections.length);
      for (final expectedConnection in expectedConnections) {
        expect(extractor.connections, contains(expectedConnection));
      }
    });

    test('normal to packed array', () async {
      final sub1 = BridgeModule('sub1')
        ..createPort('mySrc', PortDirection.output, width: 3 * 2 * 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createArrayPort('myDst', PortDirection.input,
            dimensions: [3, 2], elementWidth: 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      final src = sub1.port('mySrc');
      final dst = sub2.port('myDst');
      connectPorts(src, dst);

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      final expectedConnections = <AdHocConnection>[
        AdHocConnection(
          sub1.port('mySrc[7:0]'),
          sub2.port('myDst[0][0]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[15:8]'),
          sub2.port('myDst[0][1]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[23:16]'),
          sub2.port('myDst[1][0]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[31:24]'),
          sub2.port('myDst[1][1]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[39:32]'),
          sub2.port('myDst[2][0]'),
        ),
        AdHocConnection(
          sub1.port('mySrc[47:40]'),
          sub2.port('myDst[2][1]'),
        ),
      ];

      expect(extractor.connections.length, expectedConnections.length);
    });
  });

  group('net connections', () {
    test('ad hoc simple', () async {
      final sub1 = BridgeModule('sub1')
        ..createPort('mySrc', PortDirection.inOut, width: 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createPort('myDst', PortDirection.inOut, width: 8);
      final middleMan = BridgeModule('middle_man')
        ..createPort('listener', PortDirection.inOut, width: 8)
        ..createPort('noisy', PortDirection.inOut, width: 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2)
        ..addSubModule(middleMan);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make connections
      connectPorts(
        sub1.port('mySrc'),
        sub2.port('myDst'),
      );
      connectPorts(
        sub2.port('myDst'),
        middleMan.port('listener'),
      );
      connectPorts(
        middleMan.port('noisy'),
        sub1.port('mySrc'),
      );

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      final ports = [
        sub1.port('mySrc'),
        sub2.port('myDst'),
        middleMan.port('listener'),
        middleMan.port('noisy'),
      ];

      expect(
          extractor.connections.length, ports.length * (ports.length - 1) ~/ 2);

      for (final p in ports) {
        for (final q in ports) {
          if (p != q) {
            expect(
              extractor.connections,
              contains(AdHocConnection(p, q)),
            );
          }
        }
      }
    });

    test('ad hoc all dsts', () async {
      final sub1 = BridgeModule('sub1')
        ..createPort('myDst1', PortDirection.inOut, width: 8);
      final sub2 = BridgeModule('sub2')
        ..createPort('myDst2', PortDirection.inOut, width: 8);
      final top = BridgeModule('top')
        ..createPort('mySrc', PortDirection.inOut, width: 8)
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // make connections
      connectPorts(
        top.port('mySrc'),
        sub1.port('myDst1'),
      );
      connectPorts(
        top.port('mySrc'),
        sub2.port('myDst2'),
      );

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 1);
      expect(extractor.connections.first, isA<AdHocConnection>());
      final connection = extractor.connections.first as AdHocConnection;
      expect(connection,
          AdHocConnection(sub1.port('myDst1'), sub2.port('myDst2')));
    });

    test('ad hoc all srcs', () async {
      final sub1 = BridgeModule('sub1')
        ..createPort('myDst1', PortDirection.inOut, width: 8);
      final sub2 = BridgeModule('sub2')
        ..createPort('myDst2', PortDirection.inOut, width: 8);
      final top = BridgeModule('top')
        ..createPort('mySrc', PortDirection.inOut, width: 8)
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // make connections
      connectPorts(
        sub1.port('myDst1'),
        top.port('mySrc'),
      );
      connectPorts(
        sub2.port('myDst2'),
        top.port('mySrc'),
      );

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 1);
      expect(extractor.connections.first, isA<AdHocConnection>());
      final connection = extractor.connections.first as AdHocConnection;
      expect(connection,
          AdHocConnection(sub1.port('myDst1'), sub2.port('myDst2')));
    });

    test('interface net connection', () async {
      final sub1 = BridgeModule('sub1')
        ..addInterface(MyNetIntf(), name: 'i1', role: PairRole.provider)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..addInterface(MyNetIntf(), name: 'i2', role: PairRole.consumer);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      connectInterfaces(
        sub1.interface('i1'),
        sub2.interface('i2'),
      );

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 1);
      expect(extractor.connections.first, isA<InterfaceConnection>());
      final connection = extractor.connections.first as InterfaceConnection;
      expect(
          connection,
          InterfaceConnection(
            sub1.interface('i1'),
            sub2.interface('i2'),
          ));
    });

    test('slices net connections', () async {
      final sub1 = BridgeModule('sub1')
        ..createPort('io1', PortDirection.inOut, width: 16)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createPort('io2', PortDirection.inOut, width: 16);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      connectPorts(
        sub1.port('io1[5:4]'),
        sub2.port('io2[15:14]'),
      );
      connectPorts(
        sub1.port('io1[1]'),
        sub2.port('io2[11]'),
      );

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 3);

      expect(
          extractor.connections,
          contains(AdHocConnection(
            sub1.port('io1[1]'),
            sub2.port('io2[11]'),
          )));

      for (var i = 4; i <= 5; i++) {
        expect(
            extractor.connections,
            contains(AdHocConnection(
              sub1.port('io1[$i]'),
              sub2.port('io2[${i + 10}]'),
            )));
      }
    });

    test('slices driving each other', () async {
      final sub1 = BridgeModule('sub1')
        ..createPort('io1', PortDirection.inOut, width: 16)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createPort('io2', PortDirection.inOut, width: 16);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2)
        ..createPort('ioTop', PortDirection.inOut, width: 8);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      connectPorts(
        sub1.port('io1[10:3]'),
        top.port('ioTop'),
      );
      connectPorts(
        sub2.port('io2[11:4]'),
        top.port('ioTop'),
      );

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 1);
      expect(
          extractor.connections.first,
          AdHocConnection(
            sub1.port('io1[10:3]'),
            sub2.port('io2[11:4]'),
          ));
    });

    test('bus subsets driving each other', () async {
      final sub1 = BridgeModule('sub1')
        ..createPort('io1', PortDirection.inOut, width: 8)
        ..createPort('clk', PortDirection.input);
      final sub2 = BridgeModule('sub2')
        ..createPort('io2', PortDirection.inOut, width: 8);
      final top = BridgeModule('top')
        ..addSubModule(sub1)
        ..addSubModule(sub2)
        ..createPort('ioTop', PortDirection.inOut, width: 16);

      // to make modules discoverable
      sub1.port('clk').punchUpTo(top);

      // make a connection
      connectPorts(
        sub1.port('io1'),
        top.port('ioTop[10:3]'),
      );
      connectPorts(
        sub2.port('io2'),
        top.port('ioTop[11:4]'),
      );

      await top.build();

      final extractor = ConnectionExtractor(top.subBridgeModules);

      expect(extractor.connections.length, 7);
      for (var i = 0; i < 7; i++) {
        expect(
            extractor.connections,
            contains(AdHocConnection(
              sub1.port('io1[${i + 1}]'),
              sub2.port('io2[$i]'),
            )));
      }
    });

    test('bits of port self-connected', () async {
      final mod = BridgeModule('mod');
      final port = mod.createPort('myPort', PortDirection.inOut, width: 8);

      final top = BridgeModule('top')..addSubModule(mod);

      connectPorts(port.slice(2, 1), port.slice(5, 4));

      top.pullUpPort(mod.createPort('clk', PortDirection.input));

      await top.build();

      final extractor = ConnectionExtractor([mod]);

      expect(extractor.connections.length, 2);
      expect(
          extractor.connections,
          contains(AdHocConnection(
            port[2],
            port[5],
          )));
      expect(
          extractor.connections,
          contains(AdHocConnection(
            port[1],
            port[4],
          )));
    });
  });
}
