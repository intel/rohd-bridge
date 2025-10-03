// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// inout_port_test.dart
// Unit tests for inout port behavior.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

class MyLeaf extends BridgeModule {
  MyLeaf(String instName, {int width = 1})
      : super('leafIP_$instName', name: instName) {
    createPort('${instName}_portA', PortDirection.input, width: width);
    createPort('${instName}_portB', PortDirection.inOut, width: width);
    createPort('${instName}_portC', PortDirection.output, width: width);
  }
}

class LeafIP extends BridgeModule {
  LeafIP(String instName, {int width = 1})
      : super('leafIP_$instName', name: instName) {
    createPort('portA', PortDirection.input, width: width);
    createPort('portB', PortDirection.inOut, width: width);
    createPort('portC', PortDirection.output, width: width);
  }
}

void main() {
  test('Common parent test', () {
    final ip1 = BridgeModule('leafIP', name: 'ip1');
    final ip2 = BridgeModule('leafIP', name: 'ip2');
    final ip3 = BridgeModule('leafIP', name: 'ip3');

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA');
    final parB = BridgeModule('parB');

    final parATop = BridgeModule('parATop')
      ..addSubModule(parA)
      ..addSubModule(parB);

    parA
      ..addSubModule(ip1)
      ..addSubModule(ip2);

    parB.addSubModule(ip3);

    soc.addSubModule(parATop);

    final a = findCommonParent(ip1, parATop);
    final ab = findCommonParent(ip1, ip2);
    final abc = findCommonParent(ip1, ip3);

    expect(a, parATop);
    expect(ab, parA);
    expect(abc, parATop);
  });
  test('Inout port connection, sibling instances', () async {
    final ip1 = LeafIP('ip1');
    final ip2 = LeafIP('ip2');

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA');

    final parATop = BridgeModule('parATop')..addSubModule(parA);

    parA
      ..addSubModule(ip1)
      ..addSubModule(ip2);

    soc.addSubModule(parATop);
    connectPorts(ip1.port('portC'), ip2.port('portA'));
    connectPorts(ip1.port('portB'), ip2.port('portB'));
    soc
      ..pullUpPort(ip1.port('portA'))
      ..pullUpPort(ip2.port('portC'));

    ip1.port('portB').port.put('1');
    expect(ip1.port('portB').port.value.toInt(), 1);
    await soc.build();

    expect(ip1.parent, parA);
    expect(ip2.parent, parA);
    expect(parA.parent, parATop);
    expect(parATop.parent, soc);
  });

  test('Inout port connection, cousin instances', () async {
    final ip1 = LeafIP('ip1');
    final ip2 = LeafIP('ip2');

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA');
    final parB = BridgeModule('parB');

    final parATop = BridgeModule('parATop')
      ..addSubModule(parA)
      ..addSubModule(parB);

    parA.addSubModule(ip1);
    parB.addSubModule(ip2);

    soc.addSubModule(parATop);
    connectPorts(ip1.port('portC'), ip2.port('portA'));
    connectPorts(ip1.port('portB'), ip2.port('portB'));
    soc
      ..pullUpPort(ip1.port('portA'))
      ..pullUpPort(ip2.port('portC'));

    ip1.port('portB').port.put('1');
    expect(ip2.port('portB').port.value.toInt(), 1);

    await soc.build();

    expect(ip1.parent, parA);
    expect(ip2.parent, parB);
    expect(parA.parent, parB.parent);
    expect(ip1.parent!.parent, ip2.parent!.parent);
  });

  test('Inout - Output port connection, siblings', () async {
    final ip1 = MyLeaf('ip1', width: 2);
    final ip2 = MyLeaf('ip2', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA')
      ..addSubModule(ip1)
      ..addSubModule(ip2);

    soc.addSubModule(parA);
    connectPorts(ip1.port('ip1_portB'), ip2.port('ip2_portA'));
    soc
      ..pullUpPort(ip1.port('ip1_portA'))
      ..pullUpPort(ip2.port('ip2_portC'));

    await soc.build();
    ip1.port('ip1_portB').port.put('10');
    expect(ip2.port('ip2_portA').port.value.toInt(), 2);

    expect(ip1.parent, parA);
    expect(ip1.parent!.parent, ip2.parent!.parent);
  });

  test('Output - Inout port connection, siblings', () async {
    final ip1 = MyLeaf('ip1', width: 2);
    final ip2 = MyLeaf('ip2', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA')
      ..addSubModule(ip1)
      ..addSubModule(ip2);

    soc.addSubModule(parA);
    connectPorts(ip1.port('ip1_portC'), ip2.port('ip2_portB'));
    soc
      ..pullUpPort(ip1.port('ip1_portA'))
      ..pullUpPort(ip2.port('ip2_portC'));

    await soc.build();

    ip1.port('ip1_portC').port.put('10');
    expect(ip2.port('ip2_portB').port.value.toInt(), 2);
    expect(ip1.parent, parA);
    expect(ip1.parent!.parent, ip2.parent!.parent);
  });

  test('Input - Inout port connection, siblings', () async {
    final ip1 = MyLeaf('ip1', width: 2);
    final ip2 = MyLeaf('ip2', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA')
      ..addSubModule(ip1)
      ..addSubModule(ip2);

    soc.addSubModule(parA);
    connectPorts(ip2.port('ip2_portB'), ip1.port('ip1_portA'));
    soc
      ..pullUpPort(ip1.port('ip1_portC'))
      ..pullUpPort(ip2.port('ip2_portC'));

    await soc.build();

    ip2.port('ip2_portB').port.put('10');
    expect(ip1.port('ip1_portA').port.value.toInt(), 2);

    expect(ip1.parent, parA);
    expect(ip1.parent!.parent, ip2.parent!.parent);
  });

  test('Inout - Input port connection, siblings', () async {
    final ip1 = MyLeaf('ip1', width: 2);
    final ip2 = MyLeaf('ip2', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA')
      ..addSubModule(ip1)
      ..addSubModule(ip2);

    soc.addSubModule(parA);
    connectPorts(ip1.port('ip1_portB'), ip2.port('ip2_portA'));
    soc
      ..pullUpPort(ip1.port('ip1_portC'))
      ..pullUpPort(ip2.port('ip2_portC'));

    await soc.build();

    ip1.port('ip1_portB').port.put('10');
    expect(ip2.port('ip2_portA').port.value.toInt(), 2);

    expect(ip1.parent, parA);
    expect(ip1.parent!.parent, ip2.parent!.parent);
  });

  test('Inout pullup', () async {
    final ip1 = MyLeaf('ip1', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA')..addSubModule(ip1);

    soc
      ..addSubModule(parA)
      ..pullUpPort(ip1.port('ip1_portB'))
      ..pullUpPort(ip1.port('ip1_portA'));
    await soc.build();

    soc.port('ip1_ip1_portB').port.put('10');
    expect(ip1.port('ip1_portB').port.value.toInt(), 2);

    expect(ip1.parent, parA);
  });

  test('Inout connect to port at top that already exists', () async {
    final ip1 = MyLeaf('ip1', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA')..addSubModule(ip1);

    soc
      ..addSubModule(parA)
      ..createPort('inoutX', PortDirection.inOut, width: 2);
    connectPorts(ip1.port('ip1_portB'), soc.port('inoutX'));
    soc
      ..pullUpPort(ip1.port('ip1_portA'))
      ..inOut('inoutX').put('10');
    expect(ip1.port('ip1_portB').port.value.toInt(), 2);
    await soc.build();
    expect(ip1.parent, parA);
    expect(parA.parent, soc);
  });

  test('Input connect to inout port at top that already exists', () async {
    final ip1 = MyLeaf('ip1', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA')..addSubModule(ip1);

    soc
      ..addSubModule(parA)
      ..createPort('inoutX', PortDirection.inOut, width: 2);
    connectPorts(soc.port('inoutX'), ip1.port('ip1_portA'));
    soc.pullUpPort(ip1.port('ip1_portC'));

    soc.inOut('inoutX').put('10');
    expect(ip1.port('ip1_portA').port.value.toInt(), 2);

    await soc.build();
    expect(ip1.parent, parA);
  });

  test('Output connect to inout port at top that already exists', () async {
    final ip1 = MyLeaf('ip1', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA')..addSubModule(ip1);

    soc
      ..addSubModule(parA)
      ..createPort('inoutX', PortDirection.inOut, width: 2);
    connectPorts(ip1.port('ip1_portC'), soc.port('inoutX'));

    ip1.port('ip1_portC').port.put('10');
    expect(soc.port('inoutX').port.value.toInt(), 2);

    await soc.build();
    expect(ip1.parent, parA);
  });

  test('Inout connect to input/output port at top that already exists',
      () async {
    final ip1 = MyLeaf('ip1', width: 2);
    final ip2 = MyLeaf('ip1', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA')
      ..addSubModule(ip1)
      ..addSubModule(ip2);

    soc
      ..addSubModule(parA)
      ..pullUpPort(ip1.port('ip1_portC'))
      ..createPort('inputx', PortDirection.input, width: 2);
    connectPorts(soc.port('inputx'), ip1.port('ip1_portB'));
    soc.port('inputx').port.put('10');
    expect(ip1.port('ip1_portB').port.value.toInt(), 2);

    soc.createPort('outputx', PortDirection.output, width: 2);
    connectPorts(ip2.port('ip1_portB'), soc.port('outputx'));

    ip2.port('ip1_portB').port.put('10');
    expect(soc.port('outputx').port.value.toInt(), 2);

    ip1.port('ip1_portB').port.put('10');

    await soc.build();
    expect(ip1.parent, parA);
  });

  test('Inout connect x', () async {
    final ip1 = MyLeaf('ip1', width: 2);
    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA');

    soc.addSubModule(parA);
    parA.addSubModule(ip1);
    soc.addOutput('outputX', width: 2); // output
    ip1.inOut('ip1_portB'); // inout

    soc.pullUpPort(ip1.port('ip1_portA'));
    connectPorts(ip1.port('ip1_portB'), soc.port('outputX'));
    ip1.port('ip1_portB').port.put('10');
    expect(soc.port('outputX').port.value.toInt(), 2);

    await soc.build();
    expect(ip1.parent, parA);
  });

  test('Inout - Output port connection, cousin instances', () async {
    final ip1 = MyLeaf('ip1', width: 2);
    final ip2 = MyLeaf('ip2', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA');
    final parB = BridgeModule('parB');

    parA.addSubModule(ip1);
    parB.addSubModule(ip2);

    soc
      ..addSubModule(parA)
      ..addSubModule(parB);
    connectPorts(ip1.port('ip1_portB'), ip2.port('ip2_portA'));
    soc
      ..pullUpPort(ip1.port('ip1_portA'))
      ..pullUpPort(ip2.port('ip2_portC'));

    await soc.build();
    ip1.port('ip1_portB').port.put('10');
    expect(ip2.port('ip2_portA').port.value.toInt(), 2);

    expect(ip1.parent, parA);
    expect(ip1.parent!.parent, ip2.parent!.parent);
  });

  test('Input - Inout port connection, cousin instances', () async {
    final ip1 = MyLeaf('ip1', width: 2);
    final ip2 = MyLeaf('ip2', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA');
    final parB = BridgeModule('parB');

    parA.addSubModule(ip1);
    parB.addSubModule(ip2);

    soc
      ..addSubModule(parA)
      ..addSubModule(parB);
    connectPorts(ip2.port('ip2_portB'), ip1.port('ip1_portA'));
    soc
      ..pullUpPort(ip1.port('ip1_portC'))
      ..pullUpPort(ip2.port('ip2_portC'));

    await soc.build();

    ip2.port('ip2_portB').port.put('10');
    expect(ip1.port('ip1_portA').port.value.toInt(), 2);

    expect(ip1.parent, parA);
    expect(ip1.parent!.parent, ip2.parent!.parent);
  });

  test('Inout - Input port connection, cousin instances', () async {
    final ip1 = MyLeaf('ip1', width: 2);
    final ip2 = MyLeaf('ip2', width: 2);

    final soc = BridgeModule('soc');
    final parA = BridgeModule('parA');
    final parB = BridgeModule('parB');

    parA.addSubModule(ip1);
    parB.addSubModule(ip2);

    soc
      ..addSubModule(parA)
      ..addSubModule(parB);
    connectPorts(ip1.port('ip1_portB'), ip2.port('ip2_portA'));
    soc
      ..pullUpPort(ip1.port('ip1_portC'))
      ..pullUpPort(ip2.port('ip2_portC'));

    await soc.build();

    ip1.port('ip1_portB').port.put('10');
    expect(ip2.port('ip2_portA').port.value.toInt(), 2);

    expect(ip1.parent, parA);
    expect(ip1.parent!.parent, ip2.parent!.parent);
  });

  test('Sliced-full Inout port connection, sibling instances', () async {
    final soc = BridgeModule('soc')
      ..createPort('inoutX', PortDirection.inOut, width: 4);

    final ipA = BridgeModule('ipA')
      ..createPort('inoutX1', PortDirection.inOut)
      ..createPort('inoutX2', PortDirection.inOut)
      ..createPort('inoutX3', PortDirection.inOut)
      ..createPort('inoutX4', PortDirection.inOut)
      ..createPort('outputX', PortDirection.output, width: 4);

    final parA = BridgeModule('parA')..addSubModule(ipA);

    soc.addSubModule(parA);
    connectPorts(ipA.port('inoutX1'), soc.port('inoutX[0]'));
    connectPorts(ipA.port('inoutX2'), soc.port('inoutX[1]'));
    connectPorts(ipA.port('inoutX3'), soc.port('inoutX[2]'));
    connectPorts(ipA.port('inoutX4'), soc.port('inoutX[3]'));
    soc.pullUpPort(ipA.port('outputX'));

    await soc.build();
    ipA.port('inoutX1').port.put('1');
    ipA.port('inoutX2').port.put('1');
    ipA.port('inoutX3').port.put('1');
    ipA.port('inoutX4').port.put('1');

    expect(soc.port('inoutX').port.value.toInt(), 15);
  });

  test(
      'Sliced-full Inout port connection, '
      'sibling instances, reversed driver', () async {
    final soc = BridgeModule('soc')
      ..createPort('inoutX', PortDirection.inOut, width: 4);

    final ipA = BridgeModule('ipA')
      ..createPort('inoutX1', PortDirection.inOut)
      ..createPort('inoutX2', PortDirection.inOut)
      ..createPort('inoutX3', PortDirection.inOut)
      ..createPort('inoutX4', PortDirection.inOut)
      ..createPort('outputX', PortDirection.output, width: 4);

    final parA = BridgeModule('parA')..addSubModule(ipA);

    soc.addSubModule(parA);
    connectPorts(soc.port('inoutX[0]'), ipA.port('inoutX1'));
    connectPorts(soc.port('inoutX[1]'), ipA.port('inoutX2'));
    connectPorts(soc.port('inoutX[2]'), ipA.port('inoutX3'));
    connectPorts(soc.port('inoutX[3]'), ipA.port('inoutX4'));
    soc.pullUpPort(ipA.port('outputX'));

    await soc.build();
    ipA.port('inoutX1').port.put('1');
    ipA.port('inoutX2').port.put('1');
    ipA.port('inoutX3').port.put('1');
    ipA.port('inoutX4').port.put('1');
    expect(soc.port('inoutX').port.value.toInt(), 15);
  });

  test(
      'Sliced-Sliced Inout port connection,through hierarchy, '
      'PENDING ROHD CHANGES', () async {
    final soc = BridgeModule('soc')
      ..createPort('inoutX', PortDirection.inOut, width: 4);

    final ipA = BridgeModule('ipA')
      ..createPort('inoutX1', PortDirection.inOut, width: 4)
      ..createPort('outputX', PortDirection.output, width: 4);

    final parA = BridgeModule('parA')..addSubModule(ipA);

    soc.addSubModule(parA);
    connectPorts(ipA.port('inoutX1[1]'), soc.port('inoutX[0]'));
    connectPorts(ipA.port('inoutX1[2]'), soc.port('inoutX[1]'));
    connectPorts(ipA.port('inoutX1[3]'), soc.port('inoutX[2]'));
    connectPorts(ipA.port('inoutX1[0]'), soc.port('inoutX[3]'));
    soc.pullUpPort(ipA.port('outputX'));

    await soc.build();
    ipA.port('inoutX1').port.put('1110');
    expect(soc.port('inoutX').port.value.toInt(), 7);
  });

  test('Sliced-Sliced Inout port connection, sibling instances', () async {
    final soc = BridgeModule('soc');
    final ipA = BridgeModule('ipA')
      ..createPort('inoutX1', PortDirection.inOut, width: 4)
      ..createPort('outputX', PortDirection.output, width: 4);

    final ipB = BridgeModule('ipB')
      ..createPort('inoutX1', PortDirection.inOut, width: 4)
      ..createPort('inputX', PortDirection.input, width: 4);

    soc
      ..addSubModule(ipA)
      ..addSubModule(ipB);
    connectPorts(ipA.port('inoutX1[0]'), ipB.port('inoutX1[3]'));
    connectPorts(ipA.port('inoutX1[1]'), ipB.port('inoutX1[2]'));
    connectPorts(ipA.port('inoutX1[2]'), ipB.port('inoutX1[1]'));
    connectPorts(ipA.port('inoutX1[3]'), ipB.port('inoutX1[0]'));
    soc.pullUpPort(ipA.port('outputX'));

    await soc.build();
    ipA.port('inoutX1').port.put('1110');
    expect(ipB.port('inoutX1').port.value.toInt(), 7);
  });

  test('pull up sliced inout', () async {
    final leaf = BridgeModule('leaf')..addInOut('myInOut', null, width: 8);

    final leaf2 = BridgeModule('leaf2')..addInOut('myInOut', null, width: 8);

    leaf.addSubModule(leaf2);
    leaf2.inOutSource('myInOut') <= leaf.inOut('myInOut');

    final top = BridgeModule('top')
      ..addSubModule(leaf)
      ..createPort('myTopInout', PortDirection.inOut, width: 8);

    top.port('myTopInout[7:5]').gets(leaf.port('myInOut[5:3]'));
    leaf.createPort('inoutXX', PortDirection.inOut, width: 8);

    top
        .createPort('inoutX', PortDirection.inOut, width: 4)
        .gets(leaf.port('inoutXX[3:0]'));

    await top.build();

    top.port('myTopInout').port.put('00000000');
    leaf.port('myInOut').port.put('11111111');
    expect(top.port('myTopInout').port.value.toInt(), 224);
  });
}
