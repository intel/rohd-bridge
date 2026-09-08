// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// intermediate_signal_name_test.dart
// Tests for the intermediateSignalName parameter on connectPorts.
//
// 2026 July
// Author: Adin De'Rosier <adin.derosier@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

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
      test('path name fallback: ${names.description}', () async {
        final (:top, :src, :dst) = _buildRig();
        src.createPort('myPortOut', PortDirection.output, width: 8);
        dst.createPort('myPortIn', PortDirection.input, width: 8);

        connectPorts(src.port('myPortOut'), dst.port('myPortIn'),
            driverPathNewPortName: names.driver,
            receiverPathNewPortName: names.receiver,
            intermediateSignalName: names.intermediate);

        await top.build();
        final sv = top.generateSynth();
        if (names.expected == null) {
          expect(dst.inputSource('myPortIn').srcConnections,
              contains(src.output('myPortOut')));
        } else {
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
          intermediateSignalName: 'myLoopbackNet');

      await top.build();
      final sv = top.generateSynth();

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
          intermediateSignalName: 'myPassthroughNet');

      await top.build();
      final sv = top.generateSynth();

      expect(child.internalSignals.map((signal) => signal.name),
          contains('myPassthroughNet'));
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
          intermediateSignalName: 'clkRouted');

      grandParent.input('clk').put(1);
      expect(child.input('clk').value.toInt(), equals(1));

      await grandParent.build();
    });
  });
}
