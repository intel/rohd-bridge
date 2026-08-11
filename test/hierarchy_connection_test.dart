// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// hierarchy_connection_test.dart
// Unit tests for building and punching through hierarchy.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  group('connect ports through hierarchy', () {
    const portName1 = 'myPort1';
    const portName2 = 'myPort2';
    const putVal = 0xab;

    /// Expects mod2 drives mod1.
    Future<void> testConnection(
        BridgeModule Function(
          BridgeModule mod1,
          BridgeModule mod2,
        ) makeConnectionsAndHier,
        {dynamic matcher = 0xab,
        bool matchDirection = false}) async {
      final mod1 = BridgeModule('mod1')
        ..createPort(portName1,
            matchDirection ? PortDirection.output : PortDirection.input,
            width: 8);
      final mod2 = BridgeModule('mod2')
        ..createPort(portName2, PortDirection.output, width: 8);

      final top = makeConnectionsAndHier(mod1, mod2);

      if (mod1 != top) {
        top.pullUpPort(mod1.createPort('dummy', PortDirection.inOut));
      }
      if (mod2 != top) {
        top.pullUpPort(mod2.createPort('dummy', PortDirection.inOut));
      }

      await top.build();

      // check connection by putting a value on the wire at the source and
      // reading at destination
      mod2.output(portName2).put(putVal);
      expect((mod1.tryInput(portName1) ?? mod1.output(portName1)).value.toInt(),
          matcher);
    }

    test('in same level', () async {
      await testConnection((leaf1, leaf2) {
        final top = BridgeModule('top')
          ..addSubModule(leaf1)
          ..addSubModule(leaf2);
        connectPorts(leaf2.port(portName2), leaf1.port(portName1));
        return top;
      });
    });

    test('through multiple levels', () async {
      await testConnection((leaf1, leaf2) {
        final mid1 = BridgeModule('mid1');
        final mid2 = BridgeModule('mid2');
        final top = BridgeModule('top')
          ..addSubModule(mid1..addSubModule(leaf1))
          ..addSubModule(mid2..addSubModule(leaf2));
        connectPorts(leaf2.port(portName2), leaf1.port(portName1));

        // ensure ports actually got punched through mid levels
        expect(mid1.inputs.keys.first, contains(portName1));
        expect(mid2.outputs.keys.first, contains(portName2));

        return top;
      });
    });

    test('misaligned direction direct parent leaf connection fails', () async {
      try {
        await testConnection((parent, child) {
          parent.addSubModule(child);
          connectPorts(child.port(portName2), parent.port(portName1));
          return parent;
        });
        fail('Should have thrown an exception');
      } on RohdBridgeException catch (e) {
        expect(e.message, contains('Vertical connections'));
      }
    });

    test('direct parent leaf connection', () async {
      await testConnection(matchDirection: true, (parent, child) {
        parent.addSubModule(child);
        connectPorts(child.port(portName2), parent.port(portName1));
        return parent;
      });
    });

    test('parent through mid to leaf connection', () async {
      await testConnection(matchDirection: true, (parent, child) {
        final mid = BridgeModule('mid');
        parent.addSubModule(mid..addSubModule(child));
        connectPorts(child.port(portName2), parent.port(portName1));
        return parent;
      });
    });

    test('feed-through fails with error unsupported', () async {
      try {
        await testConnection(matchDirection: true, (leaf1, leaf2) {
          final top = BridgeModule('top')
            ..addSubModule(leaf1)
            ..addSubModule(leaf2);
          connectPorts(leaf2.port(portName2), leaf1.port(portName1));
          return top;
        });
        fail('Should have thrown an exception');
      } on RohdBridgeException catch (e) {
        expect(e.message, contains('Unhandled direction'));
        return;
      }
    });
  });

  test(
      'connection up/down with same name '
      'should keep intermediate name the same', () {
    final mid = BridgeModule('mid');
    final leaf = BridgeModule('leaf')
      ..createPort('myPortIn', PortDirection.input, width: 8)
      ..createPort('myPortOut', PortDirection.output, width: 8);
    final top = BridgeModule('top')
      ..createPort('myPortIn', PortDirection.input, width: 8)
      ..createPort('myPortOut', PortDirection.output, width: 8)
      ..addSubModule(mid..addSubModule(leaf));

    connectPorts(top.port('myPortIn'), leaf.port('myPortIn'));
    connectPorts(leaf.port('myPortOut'), top.port('myPortOut'));

    // the mid ports names should be the same if src and dst have same names
    expect(mid.tryInput('myPortIn'), isNotNull);
    expect(mid.tryOutput('myPortOut'), isNotNull);
  });

  group('pull up port', () {
    const defaultPortName1 = 'myPort1';
    const defaultPortName2 = 'myPort2';

    Future<void> testPullUp(
      BridgeModule Function(BridgeModule leaf1, BridgeModule leaf2)
          makeConnectionsAndHier, {
      String portName1 = defaultPortName1,
      String portName2 = defaultPortName2,
    }) async {
      final leaf1 = BridgeModule('leaf1')
        ..createPort(portName1, PortDirection.input, width: 8);
      final leaf2 = BridgeModule('leaf2')
        ..createPort(portName2, PortDirection.output, width: 8);

      final top = makeConnectionsAndHier(leaf1, leaf2);

      // check connection by putting a value on the wire at the source and
      // reading at destination
      top.inputs.values.first.put(0xab);
      expect(leaf1.input(portName1).value.toInt(), equals(0xab));

      leaf2.output(portName2).put(0xbc);
      expect(top.outputs.values.first.value.toInt(), equals(0xbc));

      await top.build();
    }

    test('in same level', () async {
      await testPullUp((leaf1, leaf2) => BridgeModule('top')
        ..addSubModule(leaf1)
        ..addSubModule(leaf2)
        ..pullUpPort(leaf1.port(defaultPortName1))
        ..pullUpPort(leaf2.port(defaultPortName2)));
    });

    test('through multiple levels', () async {
      await testPullUp((leaf1, leaf2) {
        final mid1 = BridgeModule('mid1');
        final mid2 = BridgeModule('mid2');
        final top = BridgeModule('top')
          ..addSubModule(mid1..addSubModule(leaf1))
          ..addSubModule(mid2..addSubModule(leaf2))
          ..pullUpPort(leaf1.port(defaultPortName1))
          ..pullUpPort(leaf2.port(defaultPortName2));

        // ensure ports actually got punched through mid levels
        expect(mid1.inputs.keys.first, contains(defaultPortName1));
        expect(mid2.outputs.keys.first, contains(defaultPortName2));

        return top;
      });
    });

    test('through multiple levels with same name at leaf', () async {
      const commonPortName = defaultPortName1;
      await testPullUp(
        // Be explicit on names here for clarity.
        // ignore: avoid_redundant_argument_values
        portName1: commonPortName,
        portName2: commonPortName,
        (leaf1, leaf2) {
          final mid1 = BridgeModule('mid1');
          final mid2 = BridgeModule('mid2');
          final top = BridgeModule('top')
            ..addSubModule(mid1..addSubModule(leaf1))
            ..addSubModule(mid2..addSubModule(leaf2));

          final topPort1 = top.pullUpPort(leaf1.port(commonPortName));
          final topPort2 = top.pullUpPort(leaf2.port(commonPortName));

          // ensure ports actually got punched through mid levels
          expect(mid1.inputs.keys.first, contains(commonPortName));
          expect(mid2.outputs.keys.first, contains(commonPortName));

          // ensure top-level port was uniquified
          expect(topPort1.portName, 'leaf1_$commonPortName');
          expect(topPort2.portName, 'leaf2_$commonPortName');

          return top;
        },
      );
    });
  });

  group('pull up array port with unpacked dimensions', () {
    test('standard port', () async {
      final top = BridgeModule('top');
      final child = BridgeModule('child');
      final childPort = child.createArrayPort('arrayPort', PortDirection.input,
          elementWidth: 8, numUnpackedDimensions: 1, dimensions: [4, 2]);
      top.addSubModule(child);

      final topPort = top.pullUpPort(childPort);

      await top.build();

      expect((topPort.port as LogicArray).numUnpackedDimensions, 1);
    });

    test('slice port whole dimension', () async {
      final top = BridgeModule('top');
      final child = BridgeModule('child')
        ..createArrayPort('arrayPort', PortDirection.input,
            elementWidth: 8, numUnpackedDimensions: 2, dimensions: [4, 2]);
      top.addSubModule(child);

      final slicePort = child.port('arrayPort[2]');
      final topPort = top.pullUpPort(slicePort);

      await top.build();

      expect((topPort.port as LogicArray).numUnpackedDimensions, 1);
    });

    test('slice port portion', () async {
      final top = BridgeModule('top');
      final child = BridgeModule('child')
        ..createArrayPort('arrayPort', PortDirection.input,
            elementWidth: 8, numUnpackedDimensions: 2, dimensions: [4, 2]);
      top.addSubModule(child);

      final slicePort = child.port('arrayPort[2:1]');
      final topPort = top.pullUpPort(slicePort);

      await top.build();

      expect((topPort.port as LogicArray).numUnpackedDimensions, 2);
    });
  });

  test('single bit to single-bit element through hierarchy', () async {
    final mod1 = BridgeModule('mod1')..addOutput('apple');
    final mod2 = BridgeModule('mod2')
      ..addInputArray('apple', LogicArray([4], 1), dimensions: [4]);

    final top = BridgeModule('Top');

    final par1 = BridgeModule('par1');
    final par2 = BridgeModule('par2');

    top.addSubModule(par1).addSubModule(mod1);
    top.addSubModule(par2).addSubModule(mod2);

    connectPorts(mod1.port('apple'), mod2.port('apple[2]'));
    top.pullUpPort(mod1.port('apple')); // so we can see RTL too

    await top.build();

    mod1.port('apple').port.put(1);
    expect(mod2.port('apple').port.value, LogicValue.of('z1zz'));
  });

  test('punchUpTo activates matching deferred interface port map', () async {
    final leaf = BridgeModule('leaf')..addInput('request_i', null);
    final intfRef = leaf.addInterface(
      PairInterface(portsFromProvider: [Logic.port('request')]),
      name: 'example',
      role: PairRole.consumer,
      connect: false,
    );
    final portMap = leaf.addPortMap(
      leaf.port('request_i'),
      intfRef.port('request'),
    );
    final top = BridgeModule('top')..addSubModule(leaf);

    final topPortRef = intfRef.port('request').punchUpTo(top);

    expect(portMap.isConnected, isTrue);

    await top.build();

    topPortRef.port.put(1);
    expect(leaf.input('request_i').value, LogicValue.one);
  });

  test('punchUpTo activates deferred interface output port map', () async {
    final leaf = BridgeModule('leaf')..addOutput('response_o');
    final intfRef = leaf.addInterface(
      PairInterface(portsFromProvider: [Logic.port('response')]),
      name: 'example',
      role: PairRole.provider,
      connect: false,
    );
    final portMap = leaf.addPortMap(
      leaf.port('response_o'),
      intfRef.port('response'),
    );
    final top = BridgeModule('top')..addSubModule(leaf);

    final topPortRef = intfRef.port('response').punchUpTo(top);

    expect(portMap.isConnected, isTrue);

    await top.build();

    leaf.output('response_o').put(1);
    expect(topPortRef.port.value, LogicValue.one);
  });

  test('punchDownTo activates matching deferred interface port map', () async {
    final top = BridgeModule('top')..addInput('request_i', null);
    final leaf = BridgeModule('leaf');
    top.addSubModule(leaf);
    final intfRef = top.addInterface(
      PairInterface(portsFromProvider: [Logic.port('request')]),
      name: 'example',
      role: PairRole.consumer,
      connect: false,
    );
    final portMap = top.addPortMap(
      top.port('request_i'),
      intfRef.port('request'),
    );

    final leafPortRef = intfRef.port('request').punchDownTo(leaf);

    expect(portMap.isConnected, isTrue);

    await top.build();

    top.input('request_i').put(1);
    expect(leafPortRef.port.value, LogicValue.one);
  });

  test('punchDownTo activates deferred interface output port map', () async {
    final top = BridgeModule('top')..addOutput('response_o');
    final leaf = BridgeModule('leaf');
    top.addSubModule(leaf);
    final intfRef = top.addInterface(
      PairInterface(portsFromProvider: [Logic.port('response')]),
      name: 'example',
      role: PairRole.provider,
      connect: false,
    );
    final portMap = top.addPortMap(
      top.port('response_o'),
      intfRef.port('response'),
    );

    final leafPortRef = intfRef.port('response').punchDownTo(leaf);

    expect(portMap.isConnected, isTrue);

    await top.build();

    leafPortRef.port.put(1);
    expect(top.output('response_o').value, LogicValue.one);
  });

  test('connectPorts activates matching deferred interface port map', () async {
    final top = BridgeModule('top')..addInput('request_i', null);
    final leaf = BridgeModule('leaf')..addInput('request_leaf_i', null);
    top.addSubModule(leaf);
    final intfRef = leaf.addInterface(
      PairInterface(portsFromProvider: [Logic.port('request')]),
      name: 'example',
      role: PairRole.consumer,
      connect: false,
    );
    final portMap = leaf.addPortMap(
      leaf.port('request_leaf_i'),
      intfRef.port('request'),
    );

    connectPorts(top.port('request_i'), intfRef.port('request'));

    expect(portMap.isConnected, isTrue);

    await top.build();

    top.input('request_i').put(1);
    expect(leaf.input('request_leaf_i').value, LogicValue.one);
  });

  test('gets activates deferred interface output port map', () async {
    final top = BridgeModule('top');
    final leaf = BridgeModule('leaf')..addOutput('response_o');
    final sink = BridgeModule('sink')..addInput('response_i', null);
    top
      ..addSubModule(leaf)
      ..addSubModule(sink);
    final intfRef = leaf.addInterface(
      PairInterface(portsFromProvider: [Logic.port('response')]),
      name: 'example',
      role: PairRole.provider,
      connect: false,
    );
    final portMap = leaf.addPortMap(
      leaf.port('response_o'),
      intfRef.port('response'),
    );

    sink.port('response_i').gets(intfRef.port('response'));

    expect(portMap.isConnected, isTrue);

    top
      ..pullUpPort(leaf.createPort('dummy_leaf', PortDirection.input))
      ..pullUpPort(sink.createPort('dummy_sink', PortDirection.input));

    await top.build();

    leaf.output('response_o').put(1);
    expect(sink.input('response_i').value, LogicValue.one);
  });

  test('hierarchy down to is itself for same module', () {
    final mod1 = BridgeModule('mod1');
    final hier = mod1.getHierarchyDownTo(mod1);
    expect(hier, isNotNull);
    expect(hier!.length, 1);
    expect(hier, contains(mod1));
  });
}
