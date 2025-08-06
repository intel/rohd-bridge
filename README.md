[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=1021755478)

[![Tests](https://github.com/intel/rohd-bridge/actions/workflows/general.yml/badge.svg?event=push)](https://github.com/intel/rohd-bridge/actions/workflows/general.yml)
[![API Docs](https://img.shields.io/badge/API%20Docs-generated-success)](https://intel.github.io/rohd-bridge/rohd_bridge/rohd_bridge-library.html)
[![Chat](https://img.shields.io/discord/1001179329411166267?label=Chat)](https://discord.gg/jubxF84yGw)
[![License](https://img.shields.io/badge/License-BSD--3-blue)](https://github.com/intel/rohd-bridge/blob/main/LICENSE)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](https://github.com/intel/rohd-bridge/blob/main/CODE_OF_CONDUCT.md)

# ROHD Bridge

ROHD Bridge is an extremely fast [ROHD](https://intel.github.io/rohd-website)-based library that helps automate generation of hardware connectivity.  Some applications include:

- Replacing legacy tools for connectivity and assembly of large hardware designs.
- Generating connectivity and hierarchy between leaf level modules, blocks, partitions, or any other hierarchy in either SOC or IP contexts.
- Using the ROHD Bridge APIs to write custom programs in [Dart](https://dart.dev/overview) with ROHD to dynamically generate connectivity.
- Build large, highly configurable designs that can be delivered in a portable, reusable way.

It is built upon the [Rapid Open Hardware Development (ROHD) framework](https://intel.github.io/rohd-website), which is a fast, flexible, and extensible generator framework for hardware design and verification.  Because it is built on ROHD, it can instantiate SystemVerilog `module`s and generate SystemVerilog for the entire design.

## Why?

### It makes connectivity and assembly easy

Generating connectivity for large designs can be difficult and tedious. Many tools and methodologies exist to try to automate, but they can add their own complexity while limiting flexibility.  ROHD Bridge makes it easy to generate connectivity in a very flexible way with minimal overhead.

### It's REALLY FAST

If you are currently using a tool that takes a non-neglible amount of time to generate connectivity, you should seriously consider ROHD Bridge. For most designs, it's effectively instant. Even for extremely large and complex designs, ROHD Bridge can connect and assemble in a few minutes.

### It's powerful and extensible

As a library, ROHD Bridge provides the ability to write custom programs using the ROHD Bridge API. Rather than using outdated languages, inventing some new language, or parsing a unique input specification format, ROHD Bridge leverages the open-source ROHD framework and is embedded into the Dart programming language.  Write any software you like to control the generation of your hardware in a modern ecosystem!

## Contributing & Support

ROHD Bridge is under active development.  If you're interested in contributing, have feedback or a question, or found a bug, please see [CONTRIBUTING.md](https://github.com/intel/rohd-bridge/blob/main/CONTRIBUTING.md).

## ROHD Bridge API User Guide

ROHD Bridge is written in the Dart programming language, which is generally regarded as easy to learn for those familiar with other popular programming languages. The  and [ROHD website](https://intel.github.io/rohd-website/get-started/setup/) have some good recommendations for getting set up.

ROHD Bridge is built on top of the [Dart](https://dart.dev/) language and [ROHD](https://intel.github.io/rohd-website), an open-source generator framework for front-end hardware development. The [Dart documentation](https://dart.dev/guides), [ROHD User Guide](https://intel.github.io/rohd-website/docs/sample-example/), and [CONTRIBUTING.md](https://github.com/intel/rohd-bridge/blob/main/CONTRIBUTING.md) are good references for getting started.

The official and latest [API documents for ROHD Bridge are available here](https://intel.github.io/rohd-bridge/rohd_bridge/rohd_bridge-library.html). To learn more about any of the APIs in this guide, check there!

A good starting point to get a feel for ROHD Bridge APIs is in the example at [`example/example.dart`](https://github.com/intel/rohd-bridge/blob/main/example/example.dart), which builds a simple hierarchy and generates some RTL from it.

### Creating Modules and Hierarchy

ROHD Bridge modules are just ROHD `Module`s with some extra added flavor to automate hierarchy and connectivity. Any hierarchical module which you want to use with ROHD Bridge should extend `BridgeModule`.

You can create a generic module without defining a class

```dart
final myMod = BridgeModule('my_mod');
```

You can also create a class which extends it to represent a specific thing

```dart
/// A doc-string for [MyMod].
class MyMod extends BridgeModule {
    MyMod() : super('my_mod') {
        // some MyMod specific behavior
    }
}
```

Hierarchy is created by calling `addSubModule`.

```dart
final myParentMod = BridgeModule('my_parent');
final mySubMod = MyMod();

// put `mySubMod` as a sub-module of `myParentMod`
myParentMod.addSubModule(mySubMod);
```

#### Adding Ports and Interfaces

Adding ports (including arrays) is easy:

```dart
final myMod = BridgeModule('my_mod');

// You can use the `createPort` and `createArrayPort` APIs, which accept an enum
myMod.createPort('my_input', PortDirection.input); // default width is 1
myMod.createPort('my_output', PortDirection.output, width: 8);
myMod.createArrayPort('my_inout_array', PortDirection.inOut, dimensions: [3, 4]);

// You can also use the base ROHD functions for adding ports, if you prefer
myMod
    ..addOutput('my_other_output', width: 5)
    ..addOutput('yet_another_output');
// note: here we used Dart's cascade notation to reduce repetition
```

Adding interfaces is easy as well:

```dart
// assume we have defined somewhere a ROHD `PairInterface` called `MyIntf`
myMod.addInterface(
    MyIntf(),
    name: 'my_intf_primary',
    role: PairRole.consumer,
);

myMod.addInterface(
    MyIntf(),
    name: 'my_intf_sideband',
    role: PairRole.consumer,

    // for the sideband, let's modify all module ports to have a "_sideband" suffix
    portUniquify: (original) => '${original}_sideband',
);
```

Note that interfaces have a `role`, which represents which side of the interface it represents. This is different from inputs vs. outputs because an interface can have ports going in both directions (plus `inOut`s!) on both sides of the interface.

Below is an example of using a pre-defined interface, but rather than letting ROHD Bridge both instantiate the interface *and* create the ports on the module boundary, we will manually map the ports.

```dart
final stdInf = myMod.addInterface(
    SomeStandardIntf(),
    name: 'my_intf1',
    role: PairRole.consumer,

    // this time, let's do manual port mapping, so don't connect
    connect: false,
);

final specialPort = myMod.createPort('special_name_for_std_port', PortDirection.input);

// specify that our specially named (physical) port maps to 
// a specific standard (logical) port from the standard interface
myMod.addPortMap(specialPort, stdIntf.port('std_port'));
```

#### Module References

A key concept in ROHD Bridge is "references" to ports, interfaces, and modules.

To refer to an instance of a `BridgeModule`, you just use the Dart variable reference to that object. When you create a module, the returned value from the constructor is a reference to that module.

```dart
// `myMod` is a variable that references a specific module
final myMod = MyMod();
```

You can use references to modules to find out relative positions in the hierarchy.

```dart
// get a full path of modules from the top down to a leaf
final pathFromTopToLeaf = myTop.getHierarchyDownTo(myLeaf);

// determine the lowest common parent between two modules
final commonParent = findCommonParent(myLeaf, someOtherModule);
```

Module names in ROHD Bridge are *not* guaranteed to be globally unique. However, if you know information about their name and relative position, there are tools to help identify the right instance(s).

```dart
// Real hierarchy:
// myTop/myUpperMid/myLowerMid/myLeaf

// Find all modules with the name "myLeaf"
myTop.findSubModules('myLeaf');

// Find modules named "myLowerMid" directly within "myUpperMid"
myTop.findSubModules('myUpperMid/myLowerMid');

// Find all modules underneath "myUpperMid" named "myLeaf"
myTop.findSubModules(RegExp('myUpperMid/.*/?myLeaf$'));

// Find one matching module, with an exception if more than 1 matches.
myTop.findSubModule('myLeaf');
```

#### Port and Interface References

In ROHD, you can reference individual signals (`Logic`s) with variables just like you can with modules.  However, ROHD Bridge also introduces `PortReference`s and `InterfaceReference`s, which have added information and automation to help with connectivity.

`PortReference`s represent an entire or part of a port (in any direction, including arrays).

```dart
// A reference to a port (in any direction) named 'port_a' on `myMod`
myMod.port('port_a');

// A reference to a slice of 'port_a'.
myMod.port('port_a[4:2]');

// A reference to a slice of an element of an array port 'arr_port_b'.
myMod.port('arr_port_b[5][2:1]');
```

`InterfaceReference`s represent an interface on a particular module and also offer ways to slice ports within that interface.

```dart
// A reference to an interface on `myMod` named 'my_interface'.
final myIntf = myMod.interface('my_interface');

// A reference to a slice of a port of `myIntf`
myIntf.port('intf_port_a[8:3]');
```

You can also do things like `slice` or index off a `PortReference`, similar to how you can in ROHD for normal `Logic`s.

#### Making Connections

One of the key capabilities of ROHD Bridge is hierarchy-aware connection between endpoints.

The `connectPorts` API takes two `PortReference`s and connects them through the hierarchy, punching ports as needed.

![Connecting ports in different scenarios](https://github.com/intel/rohd-bridge/raw/main/doc/connectPorts.png)

```dart
// make a connection between port 'a' of `mod1` and 'b' of `mod2
connectPorts(mod1.port('a'), mod2.port('b'));
```

You can also pull a port up through a hierarchy:

```dart
// pull port 'a' of `leafMod` up through the hierarchy to expose it on `topMod`
topMod.pullUpPort(leafMod.port('a'));
```

Similarly, you can use `connectInterfaces` and `pullUpInterface` to do the same with `InterfaceReference`s.

```dart
// make a (role-aware) connection between interface 'i1' on `mod1` and 'i2' on `mod2`
connectInterfaces(mod1.interface('i1'), mod2.interface('i2'));

// pull up interface 'i1' up through the hierarchy to expose it on `topMod`
topMod.pullUpInterface(leafMod.interface('i1'));
```

Note that these APIs can be called on references to modules and ports independent of their specific relative position. This provides an opportunity to *decouple hierarchy specifications and connectivity specifications*. A front-end development environment and a back-end aware partitioned environment could reuse the same connection code with different hierarchies.

```dart
/// Build a simple hierarchy for the testbench.
void buildHierarchyForTestbench(SubMod1 m1, SubMod2 m2) {
    final tbTop = BridgeModule('tbTop')
        ..addSubModule(m1)
        ..addSubModule(m2);
}

/// Build a partitioned hierarchy for backend.
void buildHierarchyForBackend(SubMod1 m1, SubMod2 m2) {
    final par1 = BridgeModule('par1')
        ..addSubModule(m1);
    final par2 = BridgeModule('par2')
        ..addSubModule(m2);

    final soc = BridgeModule('soc')
        ..addSubModule(par1)
        ..addSubModule(par2);
}

/// Connect ports between [m1] and [m2], agnostic to hierarchy.
void connectModules(SubMod1 m1, SubMod2 m2) {
    connectPorts(m1.port('a'), m2.port('a'));
}
```

#### Handling Parameters

Parameters in SystemVerilog can control generation of hardware and port widths, among other things. In ROHD (and thus ROHD Bridge), parameters cannot control port widths or generation, but can be *passed down* to leaf SystemVerilog modules. ROHD generates statically configured SystemVerilog, but can instantiate SystemVerilog with parameter values passed to it. The motivation for this restriction is so that you can use *unrestricted software* to generate your hardware, rather than be limited to only generating hardware that can be represented with overly-restrictive SystemVerilog parameter rules. This may mean you would run ROHD Bridge multiple times to create different "flavors" of your design in SystemVerilog where configuration within the hierarchy is different.

For cases where you want to pass some parameter down into the leaf nodes of your SystemVerilog design, you can use the `createParameter` and `pullUpParameter` APIs.

```dart
// register a parameter 'A' on `leaf1` with a default value of '10'
leaf1.createParameter('A', '10')

// pull up parameter 'A' from `leaf1 to `top`, exposing it at `top`
top.pullUpParameter(leaf1, 'A')
```

#### Instantiating SystemVerilog Leaves

When you have a SystemVerilog leaf module and would like to instantiate it with ROHD Bridge, you have a couple of options:

1. Manually specify all the ports, interfaces, etc. using ROHD Bridge APIs.
  
    This option allows you to use ROHD Bridge APIs to generate a shell definition for your module programmatically.

2. Process some existing representation of the module (e.g. RTL or IPXACT) to generate interface information automatically.

    This option allows you to specify ports in ways you may already use and just import that information into ROHD Bridge.

If you go with option #1, you can use APIs as described above in the user guide. For option #2, you can pass a JSON representation of the modules and interfaces into `BridgeModule.addFromJson`. *Stay tuned for additional utilities to assist in generating a schema-compliant JSON from standard languages like SystemVerilog and IPXACT.*

#### Generating SystemVerilog RTL

Because the model built is a ROHD model, you can follow the [ROHD User Guide instructions for generating outputs](https://intel.github.io/rohd-website/docs/generation/).

Alternatively, ROHD Bridge offers some automation for generating SystemVerilog and dumping to an output folder with one module per file:

```dart
await myMod.buildAndGenerateRTL();
```

----------------

Copyright (C) 2024-2025 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause
