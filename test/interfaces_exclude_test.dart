// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interfaces_exclude_test.dart
// Unit tests for exclusion functionality while connecting interfaces.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class IntfA extends PairInterface {
  final int paramA;

  IntfA({this.paramA = 1}) : super() {
    setPorts([Logic.port('fc', paramA)], [PairDirection.fromConsumer]);
    setPorts([Logic.port('fp', paramA)], [PairDirection.fromProvider]);
    setPorts([Logic.port('apple', 4)], [PairDirection.fromProvider]);
    setPorts([Logic.port('orange', 4)], [PairDirection.fromConsumer]);
  }

  @override
  IntfA clone() => IntfA(paramA: paramA);
}

class LM1 extends BridgeModule {
  late int paramA;
  LM1({this.paramA = 8, String instName = 'lm1'})
      : super('lm1', name: instName, reserveDefinitionName: false) {
    final inf1 = addInterface(
      IntfA(paramA: paramA),
      name: 'intf1',
      role: PairRole.consumer,
      connect: false,
    );

    addOutput('dummy', width: 8);

    addOutput('orange', width: 4);
    addPortMap(port('orange'), inf1.port('orange'));

    addInput('apple', Logic(name: 'apple', width: 4), width: 4);
    addPortMap(port('apple'), inf1.port('apple'));

    addOutput('fc', width: 8);
    addPortMap(port('fc'), inf1.port('fc'));
  }
}

class LM2 extends BridgeModule {
  late int paramA;
  LM2({this.paramA = 8, String instName = 'lm2'})
      : super('lm2', name: instName, reserveDefinitionName: false) {
    final inf1 = addInterface(
      IntfA(paramA: paramA),
      name: 'intf1',
      role: PairRole.provider,
      connect: false,
    );

    addOutput('dummy', width: 8);

    addOutput('apple', width: 4);
    addPortMap(port('apple'), inf1.port('apple'));

    addInput('orange', Logic(name: 'orange', width: 4), width: 4);
    addPortMap(port('orange'), inf1.port('orange'));

    addOutput('fp', width: 8);
    addPortMap(port('fp'), inf1.port('fp'));
  }
}

void main() {
  test('exclusive excludeList', () async {
    final top = BridgeModule('top');
    final par1 = BridgeModule('par1');
    final par2 = BridgeModule('par2');
    top
      ..addSubModule(par1)
      ..addSubModule(par2);
    final lm1Inst = par1.addSubModule(LM1());
    final lm2Inst = par2.addSubModule(LM2());
    connectInterfaces(lm2Inst.interface('intf1'), lm1Inst.interface('intf1'),
        exceptPorts: {'apple', 'fc', 'fp'});
    top.pullUpPort(lm2Inst.port('dummy'));
    await top.build();
    expect(par1.inputs.containsKey('intf1_apple'), false);
    expect(par2.outputs.containsKey('intf1_apple'), false);
  });

  test('incomplete excludeList', () async {
    final top = BridgeModule('top');
    final par1 = BridgeModule('par1');
    final par2 = BridgeModule('par2');
    top
      ..addSubModule(par1)
      ..addSubModule(par2);
    final lm1Inst = par1.addSubModule(LM1());
    final lm2Inst = par2.addSubModule(LM2());
    try {
      connectInterfaces(lm2Inst.interface('intf1'), lm1Inst.interface('intf1'),
          exceptPorts: {'apple', 'fc'});
      top.pullUpPort(lm2Inst.port('dummy'));
      await top.build();
      expect(par1.inputs.containsKey('intf1_apple'), false);
      expect(par2.outputs.containsKey('intf1_apple'), false);
    } on Exception catch (e) {
      expect(
          e.toString(),
          contains('Cannot connect interface intf1'
              ' at lm2 to interface intf1 at lm1'
              ' because there are unmapped ports :'
              ' {fp} on receiver'));
    }
  });

  test('default excludeList', () async {
    final top = BridgeModule('top');
    final par1 = BridgeModule('par1');
    final par2 = BridgeModule('par2');
    top
      ..addSubModule(par1)
      ..addSubModule(par2);
    final lm1Inst = par1.addSubModule(LM1());
    final lm2Inst = par2.addSubModule(LM2());
    try {
      connectInterfaces(lm2Inst.interface('intf1'), lm1Inst.interface('intf1'));
      top.pullUpPort(lm2Inst.port('dummy'));
      await top.build();
      expect(par1.outputs.length + par1.inputs.length + par1.inOuts.length,
          lm1Inst.interface('intf1').interface.ports.length);
      //Excluding the dummy port in calculation below
      expect(par2.outputs.length + par2.inputs.length + par2.inOuts.length - 1,
          lm2Inst.interface('intf1').interface.ports.length);
    } on Exception catch (e) {
      expect(
          e.toString(),
          contains('Cannot connect interface intf1'
              ' at lm2 to interface intf1 at lm1 because'
              ' there are unmapped ports :'
              ' {fc} on driver : {fp} on receiver'));
    }
  });

  test('pullUpInterface with exceptPorts', () async {
    // - BridgeModule.pullUpInterface
    //   -> passes correctly to connectUpTo, punchUpTo

    final top = BridgeModule('top');
    final leaf = LM1();
    final mid = BridgeModule('mid')..addSubModule(leaf);
    top
      ..addSubModule(mid)
      ..pullUpInterface(leaf.interface('intf1'), exceptPorts: {'fc', 'fp'});

    await top.build();

    expect(top.hasPortWithSubstring('fc'), isFalse);
    expect(top.hasPortWithSubstring('fp'), isFalse);
    expect(mid.hasPortWithSubstring('fc'), isFalse);
    expect(mid.hasPortWithSubstring('fp'), isFalse);

    expect(top.hasPortWithSubstring('apple'), isTrue);
    expect(top.hasPortWithSubstring('orange'), isTrue);
    expect(mid.hasPortWithSubstring('apple'), isTrue);
    expect(mid.hasPortWithSubstring('orange'), isTrue);
  });

  test('connectInterfaces with exceptPorts', () async {
    // - connectInterfaces
    //   -> passes correctly to InterfaceReference.connectUpTo, connectDownTo

    final top = BridgeModule('top');
    final leaf1 = LM1(instName: 'leaf1');
    final leaf2 = LM2(instName: 'leaf2');
    final mid1 = BridgeModule('mid1')..addSubModule(leaf1);
    final mid2 = BridgeModule('mid2')..addSubModule(leaf2);
    top
      ..addSubModule(mid1)
      ..addSubModule(mid2)
      ..pullUpPort(leaf2.port('dummy'));

    connectInterfaces(leaf1.interface('intf1'), leaf2.interface('intf1'),
        exceptPorts: {'fc', 'fp'});

    await top.build();

    expect(mid1.hasPortWithSubstring('fc'), isFalse);
    expect(mid1.hasPortWithSubstring('fp'), isFalse);
    expect(mid2.hasPortWithSubstring('fc'), isFalse);
    expect(mid2.hasPortWithSubstring('fp'), isFalse);
    expect(top.hasPortWithSubstring('fc'), isFalse);
    expect(top.hasPortWithSubstring('fp'), isFalse);

    expect(mid1.hasPortWithSubstring('apple'), isTrue);
    expect(mid1.hasPortWithSubstring('orange'), isTrue);
    expect(mid2.hasPortWithSubstring('apple'), isTrue);
    expect(mid2.hasPortWithSubstring('orange'), isTrue);
  });

  test('punchUpTo with exceptPorts', () async {
    //   - InterfaceReference.punchUpTo
    //     -> _connectAllPortMaps, cloneExcept, connectUpTo

    final top = BridgeModule('top');
    final leaf = LM1();
    top.addSubModule(leaf);

    leaf.interface('intf1').punchUpTo(top, exceptPorts: {'fp', 'fc'});

    await top.build();

    expect(top.hasPortWithSubstring('fp'), isFalse);
    expect(top.hasPortWithSubstring('fc'), isFalse);

    expect(top.hasPortWithSubstring('orange'), isTrue);
    expect(top.hasPortWithSubstring('apple'), isTrue);

    expect(top.interface('intf1').interface,
        isNot(equals(leaf.interface('intf1').interface)));
  });

  test('punchDownTo with exceptPorts', () async {
    //   - InterfaceReference.punchDownTo
    //     -> _connectAllPortMaps, cloneExcept, connectDownTo

    final top = LM1();
    final leaf = BridgeModule('leaf');
    top.addSubModule(leaf);

    top.interface('intf1').punchDownTo(leaf, exceptPorts: {'fp', 'fc'});

    await top.build();

    expect(leaf.hasPortWithSubstring('fp'), isFalse);
    expect(leaf.hasPortWithSubstring('fc'), isFalse);

    expect(leaf.hasPortWithSubstring('orange'), isTrue);
    expect(leaf.hasPortWithSubstring('apple'), isTrue);

    expect(top.interface('intf1').interface,
        isNot(equals(leaf.interface('intf1').interface)));
  });

  test('punchUpTo with exclusions and portUniquify', () async {
    final top = BridgeModule('top');
    final leaf = LM1();
    top.addSubModule(leaf);

    final ref = leaf.interface('intf1').punchUpTo(
          top,
          exceptPorts: {'fp', 'fc'},
          portUniquify: (logical) => 'custom_$logical',
        );

    expect(ref.interface.ports.keys, unorderedEquals(['apple', 'orange']));
    expect(top.inputs.keys, contains('custom_apple'));
    expect(top.outputs.keys, contains('custom_orange'));
    expect(top.hasPortWithSubstring('fc'), isFalse);
    expect(top.hasPortWithSubstring('fp'), isFalse);

    await top.build();
    top.input('custom_apple').put(0xa);
    leaf.output('orange').put(0x5);
    expect(leaf.input('apple').value.toInt(), 0xa);
    expect(top.output('custom_orange').value.toInt(), 0x5);
  });

  test('punchDownTo with exclusions and portUniquify', () async {
    final top = LM1();
    final leaf = BridgeModule('leaf');
    top.addSubModule(leaf);

    final ref = top.interface('intf1').punchDownTo(
          leaf,
          exceptPorts: {'fp', 'fc'},
          portUniquify: (logical) => 'custom_$logical',
        );

    expect(ref.interface.ports.keys, unorderedEquals(['apple', 'orange']));
    expect(leaf.inputs.keys, contains('custom_apple'));
    expect(leaf.outputs.keys, contains('custom_orange'));
    expect(leaf.hasPortWithSubstring('fc'), isFalse);
    expect(leaf.hasPortWithSubstring('fp'), isFalse);

    await top.build();
    top.input('apple').put(0xa);
    leaf.output('custom_orange').put(0x5);
    expect(leaf.input('custom_apple').value.toInt(), 0xa);
    expect(top.output('orange').value.toInt(), 0x5);
  });

  test('connectUpTo with exceptPorts', () async {
    //   - InterfaceReference.connectUpTo
    //     -> _connectAllPortMaps (both), receive and drive other (both)

    final top = LM1();
    final leaf = LM1();
    top.addSubModule(leaf);

    leaf
        .interface('intf1')
        .connectUpTo(top.interface('intf1'), exceptPorts: {'fp', 'fc'});

    await top.build();

    top.input('apple').put(0xA);
    leaf.output('orange').put(0x5);

    expect(top.output('orange').value.toInt(), 0x5);
    expect(leaf.input('apple').value.toInt(), 0xA);

    leaf.output('fc').put(0xFF);
    expect(top.output('fc').value.isFloating, isTrue);
  });

  test('connectDownTo with exceptPorts', () async {
    //   - InterfaceReference.connectDownTo
    //     -> _connectAllPortMaps (both), receive and drive other (both)

    final top = LM1();
    final leaf = LM1();
    top.addSubModule(leaf);

    top
        .interface('intf1')
        .connectDownTo(leaf.interface('intf1'), exceptPorts: {'fp', 'fc'});

    await top.build();

    top.input('apple').put(0xA);
    leaf.output('orange').put(0x5);

    expect(top.output('orange').value.toInt(), 0x5);
    expect(leaf.input('apple').value.toInt(), 0xA);

    leaf.output('fc').put(0xFF);
    expect(top.output('fc').value.isFloating, isTrue);
  });

  test('connectTo with exceptPorts', () async {
    //   - InterfaceReference.connectTo
    //     -> _connectAllPortMaps (both), receive and drive other (both)

    final top = BridgeModule('top');
    final leaf1 = LM1();
    final leaf2 = LM2();
    top
      ..addSubModule(leaf1)
      ..addSubModule(leaf2);

    leaf1
        .interface('intf1')
        .connectTo(leaf2.interface('intf1'), exceptPorts: {'fp', 'fc'});

    top
      ..pullUpPort(leaf2.port('dummy'))
      ..pullUpPort(leaf1.port('dummy'));

    await top.build();

    leaf2.output('apple').put(0xA);
    leaf1.output('orange').put(0x5);

    expect(leaf1.input('apple').value.toInt(), 0xA);
    expect(leaf2.input('orange').value.toInt(), 0x5);
  });
}

extension on BridgeModule {
  /// Indicates if any port in this module contains [subName] as a substring.
  bool hasPortWithSubstring(String subName) =>
      inputs.keys.any((element) => element.contains(subName)) ||
      outputs.keys.any((element) => element.contains(subName)) ||
      inOuts.keys.any((element) => element.contains(subName));
}
