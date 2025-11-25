// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// interface_reference.dart
// Definitions for accessing interfaces.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

// we ignore this because the `_internalInterface` can be populated late, but
//  equality checks and hashCode are safe on the rest of it.
// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes

part of 'references.dart';

/// A [Reference] to an interface on a [BridgeModule].
///
/// This class provides access to a [PairInterface] that exists on the boundary
/// of a [BridgeModule]. It manages the relationship between the external
/// interface (visible from outside the module) and the optional internal
/// interface (visible from inside the module), along with the port mappings
/// between them.
class InterfaceReference<InterfaceType extends PairInterface>
    extends Reference {
  /// The name of this interface within the [module].
  final String name;

  /// The external interface instance that exists "outside" of the [module].
  ///
  /// This is the interface that other modules will connect to when establishing
  /// interface-to-interface connections.
  final InterfaceType interface;

  /// The internal interface instance that exists "inside" the [module].
  ///
  /// If `null`, then there is no internal interface representation — the
  /// interface is mapped directly to individual module ports or connected
  /// indirectly through other interfaces.
  ///
  /// If an interface is connected vertically (e.g. child up to parent) to an
  /// interface that originally did not have an [internalInterface], one will
  /// be created and connected for any [portMaps].
  InterfaceType? get internalInterface => _internalInterface;
  InterfaceType? _internalInterface;

  /// The role that this interface plays in interface connections.
  ///
  /// This determines the directionality of ports when connecting interfaces.
  final PairRole role;

  /// An unmodifiable list of all port mappings for this interface.
  ///
  /// Each [PortMap] represents a connection between a port on the interface and
  /// a port on the module. These mappings are used to resolve interface
  /// connections into physical port connections.
  late final List<PortMap> portMaps = UnmodifiableListView(_portMaps);
  final List<PortMap> _portMaps = [];

  /// All port references that belong to this interface.
  ///
  /// Returns a list of [InterfacePortReference]s for every port defined in the
  /// [interface]. These can be used to access individual ports within the
  /// interface for detailed connection control.
  List<InterfacePortReference> get ports =>
      interface.ports.keys.map(port).toList(growable: false);

  /// Whether all interface ports are fully connected to module ports.
  ///
  /// An interface is considered fully connected when every port in the
  /// [interface] has a corresponding [PortMap] that connects it to a physical
  /// port on the [module].
  ///
  /// Note: Partial connections (such as slices of interface ports) are not
  /// considered fully connected. This method does not currently verify that
  /// multiple slice connections collectively cover the entire interface port.
  bool get isFullyConnected => ports.every((port) => _portMaps.any((map) =>
      map.interfacePort == port &&
      map.isConnected &&
      map.interfacePort is! SlicePortReference));

  @override
  BridgeModule get module => super.module!;

  /// Creates a new interface reference.
  ///
  /// This constructor should only be called by [BridgeModule] when adding an
  /// interface via `addInterface()`.
  ///
  /// If [connect] is `true`, automatically creates an internal interface and
  /// establishes port mappings between the internal and external interfaces. If
  /// [portUniquify] is provided, it will be used to generate unique port names
  /// for the internal interface.
  @internal
  InterfaceReference(
      this.name, BridgeModule super.module, this.interface, this.role,
      {required bool connect,
      required String Function(String logical)? portUniquify}) {
    if (connect) {
      _internalInterface =
          module.addPairInterfacePorts(interface, role, uniquify: portUniquify);

      for (final portName in internalInterface!.ports.keys) {
        final intfPortRef = port(portName);
        _portMaps.add(
          PortMap(
            port: module.port(portUniquify?.call(portName) ?? portName),
            interfacePort: intfPortRef,
            preConnected: true, // pre-resolved since we just connectIO'd
          ),
        );
      }
    } else {
      _internalInterface = null;
    }
  }

  /// Creates an [internalInterface] on this [InterfaceReference], connecting
  /// ports to existing [portMaps] when they exist, and creating new ports
  /// otherwise.
  ///
  /// This should only be called when [internalInterface] is `null`.
  void _introduceInternalInterface() {
    assert(
        internalInterface == null,
        'Should only be called when no internal interface'
        ' was created originally.');

    _internalInterface = interface.clone() as InterfaceType;

    for (final portMap in portMaps) {
      if (portMap.isConnected) {
        portMap.connectInternalIfPresent();
      }
    }
  }

  /// Creates a mapping between an interface port and a module port.
  ///
  /// This establishes a connection between [interfacePort] (which must belong
  /// to this interface) and [port] (which must belong to this module).
  ///
  /// If [connect] is `true`, the port mapping is immediately activated. If
  /// `false`, the mapping is deferred until the interface is connected to
  /// another interface.
  ///
  /// Throws an exception if the [interfacePort] doesn't belong to this
  /// interface or if a mapping for the [port] already exists.
  PortMap addPortMap(InterfacePortReference interfacePort, PortReference port,
      {bool connect = true}) {
    if (interfacePort.interfaceReference != this) {
      throw RohdBridgeException('$interfacePort is not part of this interface '
          '$name in module $module');
    }

    final portMap = PortMap(port: port, interfacePort: interfacePort);

    if (_portMaps.contains(portMap)) {
      throw RohdBridgeException('Port map for $port already exists in $name');
    }

    if (connect) {
      portMap.connect();
    }

    _portMaps.add(portMap);

    return portMap;
  }

  /// Activates all port mappings for this interface.
  ///
  /// This method should be called when all port mappings need to be resolved
  /// and connected (e.g., when establishing an interface-to-interface
  /// connection). The [exceptPorts] parameter allows excluding specific ports
  /// from connection.
  void _connectAllPortMaps({required Set<String>? exceptPorts}) {
    for (final portMap in _portMaps.where((pm) =>
        exceptPorts == null || !exceptPorts.contains(pm.port.portName))) {
      portMap.connect();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is InterfaceReference &&
      other.name == name &&
      other.module == module &&
      other.interface == interface;

  @override
  int get hashCode => name.hashCode ^ module.hashCode ^ interface.hashCode;

  /// Gets a reference to a specific port within this interface.
  ///
  /// The [portRef] can be either a simple port name (e.g., "data") or include
  /// slicing/indexing syntax (e.g., "data[7:0]", "addr[3]").
  ///
  /// Returns either a [StandardInterfacePortReference] for simple port names or
  /// a [SliceInterfacePortReference] for sliced access.
  InterfacePortReference port(String portRef) {
    if (SlicePortReference._isSliceAccess(portRef)) {
      return SliceInterfacePortReference.fromString(this, portRef);
    }

    if (StandardPortReference._isStandardAccess(portRef)) {
      return StandardInterfacePortReference(this, portRef);
    }

    throw RohdBridgeException('Invalid port access string: $portRef');
  }

  /// Creates a copy of this interface in a parent module.
  ///
  /// This "punches up" the interface from this [module] to [newModule], which
  /// should be a parent of this module. The new interface will have the same
  /// role and be automatically connected to this interface.
  ///
  /// Parameters:
  /// - [newIntfName]: Optional new name for the interface (defaults to current
  ///   name)
  /// - [allowNameUniquification]: Whether to allow automatic name
  ///   uniquification
  /// - [exceptPorts]: Set of port names to exclude from the new interface
  /// - [portUniquify]: Function to generate unique port names
  ///
  /// If [exceptPorts] is provided, the resulting interface will exclude those
  /// ports (and thus not be of the same type). Otherwise, the new interface
  /// will be of the same type as this one.
  InterfaceReference punchUpTo(
    BridgeModule newModule, {
    String? newIntfName,
    bool allowNameUniquification = false,
    Set<String>? exceptPorts,
    String Function(String logical)? portUniquify,
  }) {
    // TODO(mkorbel1): remove restriction that it must be adjacent (https://github.com/intel/rohd-bridge/issues/13)
    if (module.parent != newModule) {
      throw RohdBridgeException(
          'The newModule must be the direct parent of this module.');
    }

    _connectAllPortMaps(exceptPorts: exceptPorts);

    final newRef = newModule.addInterface(
      interface._cloneExcept(exceptPorts: exceptPorts),
      name: newIntfName ?? name,
      role: role,
      allowNameUniquification: allowNameUniquification,
      portUniquify: portUniquify,
    );

    connectUpTo(newRef, exceptPorts: exceptPorts);

    return newRef;
  }

  /// Establishes a hierarchical "upward" connection to a parent interface.
  ///
  /// Connects this interface to [other], where [other] represents the same
  /// interface in the parent module. This sets up the proper signal flow based
  /// on the interface role:
  ///
  /// - For provider interfaces: outputs flow up, inputs flow down
  /// - For consumer interfaces: inputs flow up, outputs flow down
  /// - Shared and common ports follow interface-specific rules
  ///
  /// The [other] must be on this reference's [module]'s parent.
  void connectUpTo(InterfaceReference other, {Set<String>? exceptPorts}) {
    // TODO(mkorbel1): remove restriction that it must be adjacent (https://github.com/intel/rohd-bridge/issues/13)
    if (module.parent != other.module) {
      throw RohdBridgeException(
          "The other interface must be on the parent module of this interface's"
          ' module.');
    }

    if (other.internalInterface == null) {
      other._introduceInternalInterface();
    }

    _connectAllPortMaps(exceptPorts: exceptPorts);
    other._connectAllPortMaps(exceptPorts: exceptPorts);

    switch (role) {
      case (PairRole.provider):
        other.internalInterface!
          .._receiveOtherExcept(
              interface,
              const [
                PairDirection.fromProvider,
              ],
              exceptPorts: exceptPorts)
          .._driveOtherExcept(
              interface,
              const [
                PairDirection.fromConsumer,
                PairDirection.sharedInputs,
                PairDirection.commonInOuts,
              ],
              exceptPorts: exceptPorts);
      case (PairRole.consumer):
        other.internalInterface!
          .._receiveOtherExcept(
              interface,
              const [
                PairDirection.fromConsumer,
              ],
              exceptPorts: exceptPorts)
          .._driveOtherExcept(
              interface,
              const [
                PairDirection.fromProvider,
                PairDirection.sharedInputs,
                PairDirection.commonInOuts,
              ],
              exceptPorts: exceptPorts);
    }
  }

  /// Connects two interfaces at the same hierarchical level, sharing a parent.
  ///
  /// Establishes a peer-to-peer connection between this interface and [other].
  /// The interfaces must have opposite roles (one provider, one consumer) to
  /// ensure proper signal directionality.
  ///
  /// The [exceptPorts] parameter allows excluding specific ports from the
  /// connection. When ports are excluded, individual port connections are made
  /// rather than using bulk interface connection methods.
  ///
  /// Throws an exception if both interfaces have the same role.
  void connectTo(InterfaceReference other, {Set<String>? exceptPorts}) {
    // TODO(mkorbel1): remove restriction that it must be adjacent (https://github.com/intel/rohd-bridge/issues/13)
    if (other.module.parent != module.parent) {
      throw RohdBridgeException('Both interfaces must be on modules that share'
          ' the same parent module.');
    }

    if (other.role == role) {
      throw RohdBridgeException('Cannot connect interfaces of the same roles');
    }

    _connectAllPortMaps(exceptPorts: exceptPorts);
    other._connectAllPortMaps(exceptPorts: exceptPorts);

    final provider = role == PairRole.provider ? this : other;
    final consumer = role == PairRole.consumer ? this : other;

    provider.interface._driveOtherExcept(
        consumer.interface,
        [
          PairDirection.fromProvider,
          PairDirection.commonInOuts,
        ],
        exceptPorts: exceptPorts);

    consumer.interface._driveOtherExcept(
        provider.interface,
        [
          PairDirection.fromConsumer,
        ],
        exceptPorts: exceptPorts);
  }

  /// Creates a copy of this interface in a submodule.
  ///
  /// This "punches down" the interface from this [module] to [subModule],
  /// creating a new interface with the same role and automatically connecting
  /// it to this interface.
  ///
  /// The [newIntfName] parameter allows renaming the interface in the
  /// submodule. If [allowNameUniquification] is true, automatic name collision
  /// resolution will be applied if needed.
  ///
  /// This operation is intended for passing interfaces down the module
  /// hierarchy.
  ///
  /// The [subModule] must be a child of this interface's [module].
  InterfaceReference punchDownTo(
    BridgeModule subModule, {
    String? newIntfName,
    bool allowNameUniquification = false,
    Set<String>? exceptPorts,
    String Function(String logical)? portUniquify,
  }) {
    // TODO(mkorbel1): remove restriction that it must be adjacent (https://github.com/intel/rohd-bridge/issues/13)
    if (subModule.parent != module) {
      throw RohdBridgeException(
          'The subModule must be a direct child of this module.');
    }

    _connectAllPortMaps(exceptPorts: exceptPorts);

    final newRef = subModule.addInterface(
      interface._cloneExcept(exceptPorts: exceptPorts),
      name: newIntfName ?? name,
      role: role,
      allowNameUniquification: allowNameUniquification,
      portUniquify: portUniquify,
    );

    connectDownTo(newRef, exceptPorts: exceptPorts);

    return newRef;
  }

  /// Establishes a hierarchical "downward" connection to a child interface.
  ///
  /// Connects this interface to [other], where [other] represents the same
  /// interface in a child module. This sets up the proper signal flow based on
  /// the interface role, with signals flowing from parent to child.
  ///
  /// The [other] must be on a sub-module of this [module].
  void connectDownTo(InterfaceReference other, {Set<String>? exceptPorts}) {
    // TODO(mkorbel1): remove restriction that it must be adjacent (https://github.com/intel/rohd-bridge/issues/13)
    if (other.module.parent != module) {
      throw RohdBridgeException(
          "The other interface must be on a child module of this interface's"
          ' module.');
    }

    if (internalInterface == null) {
      _introduceInternalInterface();
    }

    _connectAllPortMaps(exceptPorts: exceptPorts);
    other._connectAllPortMaps(exceptPorts: exceptPorts);

    switch (role) {
      case (PairRole.provider):
        internalInterface!
          .._driveOtherExcept(
              other.interface,
              const [
                PairDirection.fromConsumer,
                PairDirection.sharedInputs,
                PairDirection.commonInOuts,
              ],
              exceptPorts: exceptPorts)
          .._receiveOtherExcept(
              other.interface,
              const [
                PairDirection.fromProvider,
              ],
              exceptPorts: exceptPorts);
      case (PairRole.consumer):
        internalInterface!
          .._driveOtherExcept(
              other.interface,
              const [
                PairDirection.fromProvider,
                PairDirection.sharedInputs,
                PairDirection.commonInOuts,
              ],
              exceptPorts: exceptPorts)
          .._receiveOtherExcept(
              other.interface,
              const [
                PairDirection.fromConsumer,
              ],
              exceptPorts: exceptPorts);
    }
  }

  /// Ports of [interface] that are tagged as [PairDirection.fromProvider].
  late final _interfaceFromProviderPorts =
      interface.getPorts([PairDirection.fromProvider]);

  /// Ports of [interface] that are tagged as [PairDirection.fromConsumer].
  late final _interfaceFromConsumerPorts =
      interface.getPorts([PairDirection.fromConsumer]);

  /// Ports of [interface] that are tagged as [PairDirection.commonInOuts].
  late final _interfaceFromCommonInOutPorts =
      interface.getPorts([PairDirection.commonInOuts]);

  /// Ports of [interface] that are tagged as [PairDirection.sharedInputs].
  late final _interfaceSharedInputPorts =
      interface.getPorts([PairDirection.sharedInputs]);

  @override
  // note: the name should not be able to collide with a port name for hashCode
  String toString() => 'Interface($name)';

  /// Returns a set of unmapped interface ports for this interface.
  ///
  /// This function iterates over the ports of the [interface] and checks if
  /// each port has a source connection and if its destination connections are
  /// empty. If a port satisfies these conditions, it is considered unmapped and
  /// added to the unmappedPorts set.
  ///
  /// The returned set contains the names of the unmapped ports.
  @internal
  Set<String> getUnmappedInterfacePorts() {
    final unmappedPorts = <String>{};
    final intfPorts = interface.getPorts();
    for (final portName in intfPorts.keys) {
      if (intfPorts[portName]!.srcConnections.isEmpty &&
          intfPorts[portName]!.dstConnections.isEmpty) {
        unmappedPorts.add(portName);
      }
    }

    final mappedPortNames = portMaps.map((pm) => pm.interfacePort.portName);
    unmappedPorts.removeAll(mappedPortNames);

    return unmappedPorts;
  }
}

/// Extensions on [PairInterface] to handle `exceptPorts` functionality.
extension _ExceptPairInterfaceExtensions on PairInterface {
  /// Performs the same operation as [driveOther], but excludes ports listed in
  /// [exceptPorts].
  void _driveOtherExcept(PairInterface other, Iterable<PairDirection> tags,
      {required Set<String>? exceptPorts}) {
    getPorts(tags).forEach((portName, thisPort) {
      if (exceptPorts == null || !exceptPorts.contains(portName)) {
        other.port(portName) <= thisPort;
      }
    });
  }

  /// Performs the same operation as [receiveOther], but excludes ports listed
  /// in [exceptPorts].
  void _receiveOtherExcept(PairInterface other, Iterable<PairDirection> tags,
      {required Set<String>? exceptPorts}) {
    getPorts(tags).forEach((portName, thisPort) {
      if (exceptPorts == null || !exceptPorts.contains(portName)) {
        thisPort <= other.port(portName);
      }
    });
  }

  /// Creates a copy of an interface with optional port exclusions.
  ///
  /// Returns a new [PairInterface] that contains all the same ports as the
  /// `this` interface, except for those listed in [exceptPorts]. If
  /// [exceptPorts] is null or empty, returns a complete clone.
  ///
  /// This is used internally when creating interface variants that exclude
  /// certain ports during hierarchical interface operations.
  PairInterface _cloneExcept({required Set<String>? exceptPorts}) {
    if (exceptPorts == null || exceptPorts.isEmpty) {
      return clone();
    }

    return PairInterface(
      portsFromConsumer: _getMatchPortsExcept(PairDirection.fromConsumer,
              exceptPorts: exceptPorts)
          .toList(),
      portsFromProvider: _getMatchPortsExcept(PairDirection.fromProvider,
              exceptPorts: exceptPorts)
          .toList(),
      sharedInputPorts: _getMatchPortsExcept(PairDirection.sharedInputs,
              exceptPorts: exceptPorts)
          .toList(),
      commonInOutPorts: _getMatchPortsExcept(PairDirection.commonInOuts,
              exceptPorts: exceptPorts)
          .toList(),
      modify: modify,
    );
  }

  /// Extracts ports with a specific direction tag from an interface.
  ///
  /// Returns a list of [Logic] ports from `this` that are tagged with
  /// the specified [tag] direction, excluding any ports listed in
  /// [exceptPorts]. Creates appropriate port instances ([Logic], [LogicArray],
  /// or [LogicNet]) based on the original port types.
  ///
  /// This is a utility method for interface cloning operations.
  List<Logic> _getMatchPortsExcept(PairDirection tag,
          {required Set<String>? exceptPorts}) =>
      getPorts({tag})
          .entries
          .where((e) => exceptPorts == null || !exceptPorts.contains(e.key))
          .map((e) => e.value.clone())
          .toList(growable: false);
}
