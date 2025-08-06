// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// example.dart
// Example code using the ROHD Bridge API.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

// ROHD Bridge allows a user to write their own module definitions in Dart
// classes. The `BridgeModule` class in ROHD Bridge can be extended into a new
// class and the connections can be made accordingly.

/// A sample interface.
class MyInterface extends PairInterface {
  MyInterface() {
    setPorts([
      Logic.port('a'),
      Logic.port('b'),
    ], [
      PairDirection.fromProvider
    ]);
  }

  @override
  MyInterface clone() => MyInterface();
}

// ** Defining an IP **

// In the class definition below, an IP named MyIP is defined.  The module name
// is “myIP” as is passed to the super constructor. This module explicitly
// creates 4 input and 4 output ports. Furthermore, the constructor instantiates
// two interfaces, intf1 and intf2 of type MyInterface with distinct interface
// connection directions – consumer and provider, respectively. For each
// interface instance, pairConnectIO creates the interface ports in the module.

/// A sample leaf IP.
class MyIP extends BridgeModule {
  /// A reference to the interface named 'intf3'.
  late final InterfaceReference<MyInterface> intf3;

  MyIP({super.name = 'myIP_inst'}) : super('myIP') {
    // create some individual ports
    for (var i = 1; i < 5; i++) {
      createPort('testPortIn$i', PortDirection.input, width: i);
      createPort('testPortOut$i', PortDirection.output, width: i);
    }

    // instantiate interface intf1 and create corresponding physical ports
    addInterface(MyInterface(), name: 'intf1', role: PairRole.consumer);

    // instantiate interface intf2 and create corresponding physical ports
    addInterface(MyInterface(), name: 'intf2', role: PairRole.provider);

    // instantiate intf3, but don't connect, instead map a port to a an existing
    // port
    intf3 = addInterface(MyInterface(),
        name: 'intf3', role: PairRole.provider, connect: false);
    addPortMap(port('testPortOut1'), intf3.port('b'));
  }
}

// ** Specifying Connectivity **

// The code snippet below illustrates the utilization of ROHD Bridge to
// construct an SoC architecture and establish connectivity between its
// constituent modules. Within the function, module objects are instantiated,
// including ip1 and ip2 representing instances of the custom module myIP,
// alongside partitions parA and parB, and the overarching SoC module soc.
// Hierarchies are defined as parA and parB are added as sub-modules within soc,
// and ip1 and ip2 are instantiated within parA and parB, respectively.
//
// ```
//  soc
//   |-- parA
//   |    |-- ip1
//   |-- parB
//        |-- ip2
// ```
//
// Standard connectivity is established by pulling an interface from ip1 to the
// top level and connecting another to ip2.
//
// ```
//  ip1.intf1 -> parA.intf1 -> soc.intf1
//  ip1.intf2 -> parA.intf2 -> parB.intf1 -> ip2.intf1
// ```
//
// Ad-hoc connectivity is achieved through a loop, dynamically connecting input
// and output ports between ip1 and ip2, iterating through ports labeled
// "testPortOut" and "testPortIn" with varying indices. This example elegantly
// demonstrates the flexibility and functionality of the ROHD Bridge framework
// in constructing complex hierarchical systems and facilitating both standard
// and ad-hoc inter-module connectivity within a SoC environment.
//

/// Instantiate and connect [MyIP] defined above. Here `soc` is the top module
/// and `parA` and `parB` are the partitions under `soc`.
BridgeModule generateSoC() {
  // create module objects
  final soc = BridgeModule('Soc'); // create a new empty module SoC
  final parA = BridgeModule('parA'); // create a new empty module parA
  final parB = BridgeModule('parB'); // create a new empty module parB
  final ip1 = MyIP(name: 'ip1'); // create ip1 object of MyIP
  final ip2 = MyIP(name: 'ip2'); // create ip2 object of MyIP

  // define hierarchies
  soc
    ..addSubModule(parA) // instantiate parA inside SoC
    ..addSubModule(parB); // instantiate parB inside SoC
  parA.addSubModule(ip1); // instantiate ip1 inside parA
  parB.addSubModule(ip2); // instantiate ip2 inside parB

  // standard connectivity
  // export intf1 interface to SoC
  soc.pullUpInterface(ip1.interface('intf1'), newIntfName: 'intf1');

  // connect interfaces
  connectInterfaces(ip1.interface('intf2'), ip2.interface('intf1'));

  // pull up intf3 to the top
  soc.pullUpInterface(ip1.intf3);

  // adhoc connectivity
  for (var i = 1; i < 5; i++) {
    connectPorts(ip1.port('testPortOut$i'), ip2.port('testPortIn$i'));
    connectPorts(ip2.port('testPortOut$i'), ip1.port('testPortIn$i'));
  }

  return soc;
}

// The main function is the primary entry point for the Dart program.
Future<void> main() async {
  // First create and build our SOC
  final soc = generateSoC();
  await soc.buildAndGenerateRTL(outputPath: 'output_example');
}
