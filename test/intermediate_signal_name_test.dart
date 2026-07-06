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
