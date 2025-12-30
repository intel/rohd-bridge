// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bridge_module.dart
// Definition for a `BridgeModule` and associated functions.
//
// 2024
// Authors:
//    Shankar Sharma <shankar.sharma@intel.com>
//    Suhas Virmani <suhas.virmani@intel.com>
//    Max Korbel <max.korbel@intel.com>

import 'dart:collection';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:logging/logging.dart';
import 'package:rohd/rohd.dart';
// Use ROHD implementation imports for access to internal utilities.
// ignore: implementation_imports
import 'package:rohd/src/collections/traverseable_collection.dart';
// Use ROHD implementation imports for access to internal utilities.
// ignore: implementation_imports
import 'package:rohd/src/utilities/sanitizer.dart';
// Use ROHD implementation imports for access to internal utilities.
// ignore: implementation_imports
import 'package:rohd/src/utilities/uniquifier.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

/// A specialized module class that extends ROHD's [Module] with advanced
/// connectivity and hierarchy management capabilities.
///
/// [BridgeModule] provides enhanced functionality for creating complex hardware
/// designs, including:
/// - Interface-based connectivity with automatic port mapping
/// - Hierarchical port and interface punching operations
/// - JSON-based module definition support
/// - Parameter passing and management
/// - SystemVerilog leaf module integration
/// - Advanced connection routing between hierarchy levels
///
/// This class serves as the foundation for building scalable, well-connected
/// hardware IP modules in the ROHD Bridge framework.
class BridgeModule extends Module with SystemVerilog {
  @override
  List<SystemVerilogParameterDefinition> get definitionParameters =>
      UnmodifiableListView(_definitionParameters);
  final List<SystemVerilogParameterDefinition> _definitionParameters;

  /// Pass-through parameters used when instantiating this module in
  /// SystemVerilog.
  ///
  /// This map contains parameter name-value pairs that will be applied during
  /// module instantiation. Values can be literals or references to other
  /// parameters.
  Map<String, String> get instantiationParameters =>
      UnmodifiableMapView(_instantiationParameters);
  final Map<String, String> _instantiationParameters;

  @override
  String? definitionVerilog(String definitionType) => null;

  @override
  DefinitionGenerationType get generatedDefinitionType => isSystemVerilogLeaf
      ? DefinitionGenerationType.none
      : DefinitionGenerationType.standard;

  @override
  // since we have a "normal" `instantiationVerilog` that has module
  // instantiation ports, we can accept empty port connections
  bool get acceptsEmptyPortConnections => true;

  @override
  String instantiationVerilog(
    String instanceType,
    String instanceName,
    Map<String, String> ports,
  ) {
    final defParamNames = definitionParameters.map((e) => e.name).toSet();
    for (final instParamName in instantiationParameters.keys) {
      if (!defParamNames.contains(instParamName)) {
        throw RohdBridgeException(
            'Instantiation parameter $instParamName does not match any '
            'definition parameter in $defParamNames');
      }
    }

    return SystemVerilogSynthesizer.instantiationVerilogFor(
      module: this,

      // we get `*NONE*` from ROHD `instanceType` if it's not reserved because
      // it does not require any definition.
      instanceType: reserveDefinitionName ? definitionName : instanceType,

      instanceName: instanceName,
      ports: ports,
      parameters: instantiationParameters, // << overridden for params
      forceStandardInstantiation: true,
    );
  }

  /// Internal mapping of renamed ports for backwards compatibility.
  ///
  /// Tracks port name changes where the key is the new name and the value is
  /// the original port name. This allows connections to be made using either
  /// the original or renamed port names.
  late final Map<String, String> renamedPorts =
      UnmodifiableMapView(_renamedPorts);
  final Map<String, String> _renamedPorts = {};

  final Map<String, InterfaceReference> _interfaces = {};

  /// Unmodifiable map of all interfaces added to this module.
  ///
  /// Maps interface names to their corresponding [InterfaceReference] objects,
  /// providing access to interface ports, roles, and connection state.
  late final Map<String, InterfaceReference> interfaces =
      UnmodifiableMapView(_interfaces);

  @override
  Module? get parent => _isBuildingOrHasBuilt ? super.parent : _rbParent;

  /// Tracks whether the module build process has started or completed.
  ///
  /// This flag ensures that certain API restrictions are enforced during and
  /// after the build process to maintain consistency with ROHD's module
  /// building semantics.
  bool _isBuildingOrHasBuilt = false;

  /// Prepares this module and all submodules for the upcoming build process.
  ///
  /// This method switches the module to build-compatible mode by setting
  /// internal flags and recursively preparing all submodules. It ensures that
  /// API calls during build don't conflict with ROHD's base [Module.build].
  void _warnBuilding() {
    _isBuildingOrHasBuilt = true;
    for (final subMod in _rbSubModules) {
      subMod._warnBuilding();
    }
  }

  @override
  Future<void> build() async {
    _warnBuilding();

    await super.build();

    if (_rbParent != null && _rbParent != super.parent) {
      throw RohdBridgeException(
          'After build, the ROHD Bridge assigned parent ${_rbParent?.name}'
          ' did not match the resolved parent ${parent?.name}');
    }

    for (final expectedSubMod in _rbSubModules) {
      if (!subModules.contains(expectedSubMod)) {
        throw RohdBridgeException(
            'After build, the ROHD Bridge sub-module ${expectedSubMod.name}'
            ' was not found in the resolved'
            ' sub-modules ${subModules.map((e) => e.name).toList()}');
      }
    }
  }

  /// The parent module in the ROHD Bridge hierarchy.
  ///
  /// This is set when the module is added as a submodule via [addSubModule].
  BridgeModule? _rbParent;

  /// Provides access to submodules before and after the build process.
  ///
  /// Before [build] is called, this returns the ROHD Bridge-specific submodules
  /// added via [addSubModule]. After build, it returns the same collection as
  /// the base [Module.subModules].
  @override
  Iterable<Module> get subModules {
    if (_isBuildingOrHasBuilt) {
      return super.subModules;
    }

    // if not built, then return the ROHD Bridge sub-modules
    return _rbSubModules.toList(growable: false);
  }

  /// All submodules that are instances of [BridgeModule].
  ///
  /// This filtered view provides access to only the BridgeModule submodules,
  /// which support the enhanced connectivity and hierarchy features.
  Iterable<BridgeModule> get subBridgeModules =>
      subModules.whereType<BridgeModule>();

  /// Internal collection of submodules added via [addSubModule].
  final Set<BridgeModule> _rbSubModules = {};

  /// Controls whether port and interface names can be automatically uniquified.
  ///
  /// When `false`, port and interface names passing through this module will
  /// never be automatically modified to resolve naming conflicts. When `true`,
  /// the module can automatically generate unique names when conflicts occur
  /// during hierarchy operations.
  final bool allowUniquification;

  /// Name uniquifier for module ports to prevent naming conflicts.
  final _portUniquifier = Uniquifier();

  /// Name uniquifier for module interfaces to prevent naming conflicts.
  final _interfaceUniquifier = Uniquifier();

  /// Updates the port name uniquifier when a new port is created.
  ///
  /// This method ensures that port names don't conflict with renamed ports and
  /// reserves the name in the uniquifier. It's called automatically when ports
  /// are added to maintain naming consistency.
  void _handleNewPortName(String name) {
    // if this name has been used as a new name in a rename
    if (_renamedPorts.containsKey(name)) {
      throw RohdBridgeException(
          'Name $name already used to rename the port ${_renamedPorts[name]} '
          'and cannot be used.');
    }

    // If the name is already taken, then presumably another API just reserved
    // it, so go ahead and try to create the port. If the port truly conflicts,
    // then the base [Module] implementation will take care of verification.
    if (_portUniquifier.isAvailable(name, reserved: true)) {
      _portUniquifier.getUniqueName(initialName: name, reserved: true);
    }
  }

  /// Indicates whether this module represents an external SystemVerilog leaf.
  ///
  /// When `true`, this [BridgeModule] represents an existing SystemVerilog
  /// module definition that should not generate new SystemVerilog code.
  /// Instead, it serves as a bridge to connect to external IP blocks.
  final bool isSystemVerilogLeaf;

  /// Creates a new [BridgeModule] with enhanced connectivity capabilities.
  ///
  /// The [definitionName] specifies the module name used in SystemVerilog
  /// generation. For external SystemVerilog modules, this should match the
  /// existing module name exactly.
  ///
  /// The [name] is the instance name when instantiated of this module instance.
  /// If the instance name of this module is important to keep consistent, you
  /// should set [reserveName] to `true` so it will not change.
  ///
  /// Reservation of [name]s and [definitionName]s will cause an exception to be
  /// thrown during SystemVerilog generation if it is not possible to maintain
  /// the reserved name.
  ///
  /// If [isSystemVerilogLeaf] is `true`, then this module is a leaf
  /// SystemVerilog module, meaning it is not generated by ROHD Bridge and
  /// should not generate a SystemVerilog definition.  Also, it means
  /// [reserveDefinitionName] must be `true` to ensure that the definition name
  /// is reserved for the SystemVerilog module.
  BridgeModule(
    String definitionName, {
    List<SystemVerilogParameterDefinition>? definitionParameters,
    Map<String, String>? instantiationParameters,
    String? name,
    super.reserveDefinitionName = true,
    super.reserveName,
    this.allowUniquification = true,
    this.isSystemVerilogLeaf = false,
  })  : _definitionParameters = List.of(definitionParameters ?? const []),
        _instantiationParameters = Map.of(instantiationParameters ?? const {}),
        super(
          definitionName: definitionName,
          name: name ?? definitionName,
        ) {
    if (isSystemVerilogLeaf && !reserveDefinitionName) {
      throw RohdBridgeException(
          'If isSystemVerilogLeaf is true, then reserveDefinitionName must'
          ' also be true.');
    }
  }

  /// Creates a [BridgeModule] from a JSON module description.
  ///
  /// This factory constructor parses JSON content (typically constructed by
  /// tools parsing other specifications) to automatically create a module with
  /// the appropriate ports, interfaces, and parameters.
  ///
  /// The JSON should contain module metadata including module name and
  /// parameters, port definitions with directions and widths, interface
  /// definitions and port mappings, and complex port structures and member
  /// mappings.
  ///
  /// The [jsonContents] contains the JSON object with the module definition.
  /// The [name] provides an optional instance name override, and [reserveName]
  /// controls whether to reserve the instance name.
  ///
  /// The created module is automatically marked as a SystemVerilog leaf since
  /// it represents an existing hardware description.
  factory BridgeModule.fromJson(
    Map<String, dynamic> jsonContents, {
    String? name,
    bool reserveName = false,
  }) {
    final definitionName = jsonContents['name']! as String;

    return BridgeModule(
      definitionName,
      name: name,
      reserveName: reserveName,
      allowUniquification: false,
      isSystemVerilogLeaf: true,
    )..addFromJson(jsonContents);
  }

  /// Map of struct member names to their corresponding packed bit slice ranges.
  ///
  /// This map enables access to individual struct members using dot notation
  /// (e.g., "mystruct.field") by mapping the logical member name to the actual
  /// bit range specification in the packed logic port.
  ///
  /// To add to this map, use [addStructMap].
  Map<String, PortReference> get structMap => UnmodifiableMapView(_structMap);
  final Map<String, PortReference> _structMap = {};

  /// Creates a mapping from [structFieldFullName] to a [PortReference], so that
  /// each time [port] receives [structFieldFullName], it will actually return
  /// the specified [reference].
  ///
  /// This is intended for mapping struct members to their corresponding slices
  /// of actual ports on a [BridgeModule].  The [structFieldFullName] must be a
  /// hierarchical name liked "myStruct.myField" and contain at least one `.`.
  void addStructMap(String structFieldFullName, PortReference reference) {
    if (!structFieldFullName.contains('.')) {
      throw RohdBridgeException(
          'Struct field name $structFieldFullName must contain a `.`');
    }

    _structMap[structFieldFullName] = reference;
  }

  /// Adds an input array port with enhanced name management.
  ///
  /// Creates a multi-dimensional input array port with automatic name conflict
  /// resolution. If [source] is not provided, a default [LogicArray] will be
  /// created with the specified characteristics.
  ///
  /// If [source] is `null`, then a default port will be created.
  @override
  LogicArray addInputArray(
    String name,
    Logic? source, {
    List<int> dimensions = const [1],
    int elementWidth = 1,
    int numUnpackedDimensions = 0,
  }) {
    _handleNewPortName(name);

    final inArr = super.addInputArray(
        name,
        source ??
            LogicArray(dimensions, elementWidth,
                name: name,
                numUnpackedDimensions: numUnpackedDimensions,
                naming: Naming.mergeable),
        dimensions: dimensions,
        elementWidth: elementWidth,
        numUnpackedDimensions: numUnpackedDimensions);

    return inArr;
  }

  /// Adds an [input] in the same way as the base [Module] does.
  ///
  /// If [source] is `null`, then a default port will be created.
  @override
  Logic addInput(String name, Logic? source, {int width = 1}) {
    _handleNewPortName(name);

    final retPort = super.addInput(name,
        source ?? Logic(name: name, width: width, naming: Naming.mergeable),
        width: width);
    return retPort;
  }

  @override
  Logic addOutput(String name, {int width = 1}) {
    _handleNewPortName(name);

    final outPort = super.addOutput(name, width: width);
    return outPort;
  }

  @override
  LogicArray addOutputArray(
    String name, {
    List<int> dimensions = const [1],
    int elementWidth = 1,
    int numUnpackedDimensions = 0,
  }) {
    _handleNewPortName(name);

    return super.addOutputArray(
      name,
      dimensions: dimensions,
      elementWidth: elementWidth,
      numUnpackedDimensions: numUnpackedDimensions,
    );
  }

  /// Adds an [inOut] in the same way as the base [Module] does.
  ///
  /// If [source] is `null`, then a default port will be created.
  @override
  LogicNet addInOut(String name, Logic? source, {int width = 1}) {
    _handleNewPortName(name);

    return super.addInOut(name,
        source ?? LogicNet(name: name, width: width, naming: Naming.mergeable),
        width: width);
  }

  /// Adds an [inOut] array in the same way as the base [Module] does.
  ///
  /// If [source] is `null`, then a default port will be created.
  @override
  LogicArray addInOutArray(
    String name,
    Logic? source, {
    List<int> dimensions = const [1],
    int elementWidth = 1,
    int numUnpackedDimensions = 0,
  }) {
    _handleNewPortName(name);

    return super.addInOutArray(
      name,
      source ??
          LogicArray.net(dimensions, elementWidth,
              name: name,
              numUnpackedDimensions: numUnpackedDimensions,
              naming: Naming.mergeable),
      dimensions: dimensions,
      elementWidth: elementWidth,
      numUnpackedDimensions: numUnpackedDimensions,
    );
  }

  /// Computes the same thing as [Module.hierarchy] after [build], but can also
  /// be run before [build] with only context about ROHD Bridge-aware hierarchy.
  @override
  Iterable<Module> hierarchy() {
    Module? pModule = this;
    final hierarchyQueue = Queue<Module>();
    while (pModule != null) {
      hierarchyQueue.addFirst(pModule);
      pModule = pModule.parent;
    }
    return hierarchyQueue;
  }

  /// Adds a submodule to this module and establishes parent-child relationship.
  ///
  /// This method adds [subModule] as a child of this module and sets up the
  /// necessary parent-child relationships for ROHD Bridge hierarchy management.
  /// The submodule must not already have a parent.
  ///
  /// Returns the [subModule] for method chaining convenience.
  BridgeModuleType addSubModule<BridgeModuleType extends BridgeModule>(
      BridgeModuleType subModule) {
    if (_isBuildingOrHasBuilt) {
      throw RohdBridgeException(
          'Cannot add sub-module ${subModule.name} after build.');
    }

    _rbSubModules.add(subModule);

    if (subModule._rbParent != null) {
      throw RohdBridgeException(
          'Module ${subModule.name} already has a parent');
    }
    subModule._rbParent = this;

    return subModule;
  }

  /// Gets a reference to an interface by name.
  ///
  /// Returns the [InterfaceReference] for the interface with the specified
  /// [name]. This provides access to the interface's ports, role, and
  /// connection methods.
  ///
  /// Throws an [Exception] if no interface with the given [name] exists.
  InterfaceReference interface(String name) =>
      interfaces[name] ??
      (throw RohdBridgeException('Interface $name not found on $this'));

  /// Creates a hierarchical connection by pulling an interface up from a
  /// submodule.
  ///
  /// This method creates a copy of [subModuleIntf] at this module level and
  /// establishes the necessary port connections through the module hierarchy.
  /// It's useful for exposing submodule interfaces at higher levels.
  ///
  /// The [newIntfName] provides a preferred name for the new interface,
  /// defaulting to the original name. The [allowIntfUniquification] controls
  /// whether to allow automatic name resolution. The [exceptPorts] specifies a
  /// set of port names to exclude from the new interface, and [portUniquify]
  /// provides a function to generate unique port names during the process.
  ///
  /// The operation automatically handles port name uniquification across
  /// hierarchy levels, interface role preservation, and connection
  /// establishment between hierarchy levels.
  ///
  /// Returns a reference to the newly created interface on this module.
  InterfaceReference pullUpInterface(InterfaceReference subModuleIntf,
          {String? newIntfName,
          bool allowIntfUniquification = true,
          Set<String>? exceptPorts,
          String Function(String logical, String physical)? portUniquify}) =>
      _pullUpInterfaceAndConnect(subModuleIntf,
          newIntfName: newIntfName,
          allowIntfUniquification: allowIntfUniquification,
          exceptPorts: exceptPorts,
          portUniquify: portUniquify);

  /// Performs the funcitonality of [pullUpInterface], but also connects the
  /// top-level returned interface to [topToConnect].
  ///
  /// The purpose of this private version is so that the [_upperSourceMap] can
  /// be properly updated all the way to the top.
  ///
  /// The [exceptPorts] parameter is an optional set of strings representing the
  /// logical port names to be excluded. If provided, the interface pulled up
  /// will contain all ports except the ones specified in [exceptPorts].
  InterfaceReference _pullUpInterfaceAndConnect(
    InterfaceReference subModuleIntf, {
    required String? newIntfName,
    required bool allowIntfUniquification,
    InterfaceReference? topToConnect,
    Set<String>? exceptPorts,
    String Function(String logical, String physical)? portUniquify,
  }) {
    if (hasBuilt) {
      throw RohdBridgeException(
          'Cannot pull up interface ${subModuleIntf.name} after build.');
    }

    if (subModuleIntf.module == this) {
      return subModuleIntf;
    }

    newIntfName ??= subModuleIntf.name;

    final path = getHierarchyDownTo(subModuleIntf.module);

    if (path == null) {
      throw RohdBridgeException('Interface $subModuleIntf is not below $this');
    }

    var newIntf = subModuleIntf;

    // keep track of created interfaces so far so we can update the
    // corresponding modules' [_upperSourceMap]s
    final createdInterfaces = <InterfaceReference>[];

    final interfaceInputPortNames = subModuleIntf.interface
        .getPorts([
          PairDirection.sharedInputs,
          PairDirection.commonInOuts,
          if (subModuleIntf.role == PairRole.consumer)
            PairDirection.fromProvider
          else
            PairDirection.fromConsumer
        ])
        .keys
        .toList(growable: false);

    for (var i = path.length - 2;
        i > 0 || (i >= 0 && topToConnect == null);
        i--) {
      // uniquify again along the path, in case of another conflict
      newIntf = newIntf.punchUpTo(
        path[i] as BridgeModule,
        newIntfName: newIntfName,
        allowNameUniquification: allowIntfUniquification,
        exceptPorts: exceptPorts,
        portUniquify: portUniquify == null
            ? null
            : (original) {
                final physicalPortMaps = subModuleIntf.portMaps
                    .where((pm) => pm.interfacePort.portName == original)
                    .toList();

                if (physicalPortMaps.length != 1) {
                  // TODO(mkorbel1): write a test that hits this
                  throw RohdBridgeException(
                      'Exactly 1 physical port must be mapped to a logical port'
                      ' for port uniquification but all of physical ports'
                      ' $physicalPortMaps were mapped to'
                      ' $original on $subModuleIntf');
                }
                final physName = subModuleIntf.module
                    ._getRenamedPortName(physicalPortMaps.first.port.portName);

                return portUniquify(original, physName);
              },
      );

      createdInterfaces.add(newIntf);

      // notify all the prior-created interfaces that they can access the
      // current interface inputs via the interface that was created
      for (final createdInterface in createdInterfaces) {
        for (final portName in interfaceInputPortNames) {
          if (exceptPorts != null && exceptPorts.contains(portName)) {
            continue;
          }
          createdInterface.module._upperSourceMap[newIntf.port(portName)] =
              createdInterface.port(portName);
        }
      }
    }

    if (topToConnect != null) {
      newIntf.connectUpTo(topToConnect, exceptPorts: exceptPorts);

      for (final createdInterface in createdInterfaces) {
        for (final portName in interfaceInputPortNames) {
          createdInterface.module._upperSourceMap[topToConnect.port(portName)] =
              createdInterface.port(portName);
        }
      }
    }

    return newIntf;
  }

  /// Creates a hierarchical port connection by pulling a port up from a
  /// submodule.
  ///
  /// This method creates a new port on this module with the same direction and
  /// characteristics as [subModulePort], then establishes the necessary
  /// connections through the module hierarchy to connect them.
  ///
  /// The [newPortName] provides a preferred name for the new port,
  /// auto-generated if not provided. The [allowPortUniquification] controls
  /// whether to allow automatic name resolution.
  ///
  /// The method automatically determines the correct connection direction based
  /// on port types, creates intermediate ports through the hierarchy as needed,
  /// handles name uniquification to prevent conflicts, and establishes the
  /// physical connections between all levels.
  ///
  /// Returns a reference to the newly created port on this module.
  PortReference pullUpPort(PortReference subModulePort,
      {String? newPortName, bool allowPortUniquification = true}) {
    final uniqName = _getUniquePortName(
      subModulePort,
      initialName: newPortName,
      allowNameUniquification: allowPortUniquification,
    );

    final thisPort = subModulePort.replicateTo(this, subModulePort.direction,
        newPortName: uniqName);

    PortReference driver;
    PortReference receiver;
    if (subModulePort.direction == PortDirection.output) {
      driver = subModulePort;
      receiver = thisPort;
    } else {
      driver = thisPort;
      receiver = subModulePort;
    }

    connectPorts(
      driver,
      receiver,
      driverPathNewPortName: uniqName,
      receiverPathNewPortName: uniqName,
      allowDriverPathUniquification: allowPortUniquification,
      allowReceiverPathUniquification: allowPortUniquification,
    );

    return thisPort;
  }

  /// Creates a port reference from a string representation with advanced
  /// parsing.
  ///
  /// This method handles both simple ports and complex port references
  /// including:
  /// - Simple port names: "clk", "reset_n"
  /// - Bit ranges and indices: "data[7:0]", "addr[5]"
  /// - Struct member access: "mystruct.field" (using [structMap] lookup)
  /// - Renamed ports: automatically resolves to original port names
  ///
  /// For struct ports (containing '.'), the method looks up the actual bit
  /// slice in [structMap]. For renamed ports, it automatically resolves to the
  /// original port name while preserving any range specification.
  ///
  /// Returns a [PortReference] that can be used for connections and operations.
  ///
  /// Throws an [Exception] if a struct port is not found in [structMap].
  PortReference port(String portRefString) {
    if (portRefString.contains('.')) {
      // this is a struct port, special handling
      if (!structMap.containsKey(portRefString)) {
        throw RohdBridgeException(
            'Struct port $portRefString not found in $name');
      }

      return structMap[portRefString]!;
    } else {
      final portRefComponents =
          SlicePortReference.extractPortAccessSliceComponents(portRefString);

      if (renamedPorts.containsKey(portRefComponents.portName)) {
        return PortReference.fromString(
            this,
            portRefString.replaceFirst(
              portRefComponents.portName,
              renamedPorts[portRefComponents.portName]!,
            ));
      } else {
        return PortReference.fromString(this, portRefString);
      }
    }
  }

  /// Internal tracking map for hierarchical port connectivity optimization.
  ///
  /// This map maintains a lookup table from [PortReference] objects at parent
  /// hierarchy levels to corresponding [PortReference] objects in this module
  /// that are driven by them. It enables efficient path reuse during complex
  /// hierarchical connections, avoiding redundant port creation when
  /// connections to the same driver already exist at different hierarchy
  /// levels.
  final Map<PortReference, PortReference> _upperSourceMap = {};

  /// Creates a new port with the specified characteristics.
  ///
  /// This is a convenience method that creates a port of the given [direction]
  /// and [width], then returns a [PortReference] for immediate use in
  /// connections and operations.
  ///
  /// The [portName] must be unique within the module, [direction] specifies the
  /// port direction (input, output, or inOut), and [width] sets the bit width
  /// of the port.
  ///
  /// Returns a [PortReference] that can be used for connections and slicing.
  PortReference createPort(String portName, PortDirection direction,
      {int width = 1}) {
    switch (direction) {
      case PortDirection.input:
        addInput(portName, null, width: width);
      case PortDirection.output:
        addOutput(portName, width: width);
      case PortDirection.inOut:
        addInOut(portName, null, width: width);
    }
    return port(portName);
  }

  /// Add array port with the given [portName], [direction], [dimensions] and
  /// [elementWidth].
  PortReference createArrayPort(String portName, PortDirection direction,
      {List<int> dimensions = const [1],
      int elementWidth = 1,
      int numUnpackedDimensions = 0}) {
    switch (direction) {
      case PortDirection.input:
        addInputArray(portName, null,
            dimensions: dimensions,
            elementWidth: elementWidth,
            numUnpackedDimensions: numUnpackedDimensions);
      case PortDirection.output:
        addOutputArray(portName,
            dimensions: dimensions,
            elementWidth: elementWidth,
            numUnpackedDimensions: numUnpackedDimensions);
      case PortDirection.inOut:
        addInOutArray(portName, null,
            dimensions: dimensions,
            elementWidth: elementWidth,
            numUnpackedDimensions: numUnpackedDimensions);
    }
    return port(portName);
  }

  /// Returns a unique name for a [portRef], or throws an [Exception] if one
  /// cannot be selected.
  ///
  /// If [allowNameUniquification] is `false`, then the port name will not be
  /// uniquified.
  String _getUniquePortName(PortReference portRef,
      {bool allowNameUniquification = true, String? initialName}) {
    initialName ??= Sanitizer.sanitizeSV([
      portRef.module.name,
      portRef.toString(),
    ].join('_'));

    final uniquePortName = _portUniquifier.getUniqueName(
      initialName: initialName,
      reserved: !allowUniquification || !allowNameUniquification,
    );

    return uniquePortName;
  }

  /// Creates a mapping between a module port and an interface port.
  ///
  /// This method establishes a connection mapping between [port] (a port on
  /// this module) and [intfPort] (a port on an [Interface]).
  ///
  /// When [connect] is true, the physical connection is made immediately.
  /// Otherwise, the mapping is recorded but the actual connection is deferred.
  ///
  /// Returns a [PortMap] object representing the established mapping.
  PortMap addPortMap(PortReference port, InterfacePortReference intfPort,
          {bool connect = false}) =>
      intfPort.interfaceReference.addPortMap(intfPort, port, connect: connect);

  /// Tie off input ports of [intfRef] from to [value].
  void tieOffInterface(InterfaceReference intfRef,
      {dynamic value = 0, bool fill = false}) {
    final intf = intfRef.interface;
    final intfRole = intfRef.role;

    final portNames = intf
        .getPorts(intfRole == PairRole.consumer
            ? [PairDirection.fromProvider]
            : [PairDirection.fromConsumer])
        .keys;

    for (final portName in portNames) {
      intfRef.port(portName).tieOff(value: value, fill: fill);
    }
  }

  /// Creates a parameter definition with configurable instantiation mapping.
  ///
  /// This method creates both a parameter definition (for module definition)
  /// and configures its instantiation behavior. The parameter can either be
  /// mapped to a parent parameter or tied to a static value.
  ///
  /// The [paramName] specifies the name of the parameter to create, [value]
  /// provides the default value for the parameter, and [type] sets the
  /// SystemVerilog type. The [isMapped] controls instantiation mapping
  /// behavior: when `true`, it maps to parent parameter
  /// (`.paramName(paramName)`), and when `false`, it uses static value
  /// (`.paramName(value)`). The [mergeIfExist] allows merging with existing
  /// parameters of same name/value.
  ///
  /// When [mergeIfExist] is `true` and a parameter with the same name and value
  /// already exists, the method returns without creating a duplicate.
  ///
  /// Throws an [Exception] if a parameter with the same name but different
  /// value already exists and [mergeIfExist] is false.
  void createParameter(String paramName, String value,
      {String type = 'int', bool isMapped = false, bool mergeIfExist = false}) {
    // TODO(mkorbel1): Is it appropriate for `isMapped` to be here? Maybe we
    //  should have more robust checking and separation between creation of a
    //  parameter and applying an instantiation parameter?

    // check if a parameter with this name and value already exists
    final existingDefinitionParameter =
        definitionParameters.firstWhereOrNull((dp) => dp.name == paramName);

    if (existingDefinitionParameter != null) {
      final paramVal = existingDefinitionParameter.defaultValue;
      if (paramVal == value && mergeIfExist) {
        // if the parameter already exists at this level with same value
        // merge the parameter mappings without creating
        // additional parameters
        return;
      } else {
        // its safer to throw RohdBridgeException in this case at this stage
        // traditional tools do generate rtl with merged mappings but end up
        // failing at rtl validation due to lint issues
        throw RohdBridgeException(
            'Parameter $paramName already exists at $name. Please use a '
            'different name.');
      }
    }

    // update default parameter
    final newParam = SystemVerilogParameterDefinition(
      paramName,
      type: type,
      defaultValue: value,
    );
    _definitionParameters.add(newParam);

    // update instantiation parameters (only if not already overridden)
    if (!instantiationParameters.containsKey(paramName)) {
      _instantiationParameters[paramName] = isMapped ? paramName : value;
    }
  }

  /// Override the value of a parameter named [paramName] with [newValue].
  void overrideParameter(String paramName, String newValue) {
    if (instantiationParameters.containsKey(paramName)) {
      _instantiationParameters[paramName] = newValue;
    } else {
      throw RohdBridgeException(
          'Parameter $paramName does not exist in $name.');
    }
  }

  /// Pull up a passthrough parameter to this level
  void pullUpParameter(BridgeModule srcInst, String srcParam,
      {String? newParamName}) {
    if (hasBuilt) {
      throw RohdBridgeException(
          'Cannot pull up parameter $srcParam from ${srcInst.name}'
          ' after build.');
    }
    newParamName ??= srcParam;
    final paramValue = srcInst.instantiationParameters[srcParam];

    final paramType = srcInst.definitionParameters
        .firstWhereOrNull((param) => param.name == srcParam)
        ?.type;

    if (paramValue == null && paramType == null) {
      throw RohdBridgeException(
          'Parameter $srcParam not found in ${srcInst.name}');
    }
    final insts = getHierarchyDownTo(srcInst);

    if (insts == null) {
      throw RohdBridgeException(
          'No hierarchy found between $name and ${srcInst.name}');
    }

    for (final inst in insts) {
      inst as BridgeModule;

      if (inst == srcInst) {
        inst.overrideParameter(srcParam, newParamName);
      } else {
        inst.createParameter(newParamName, paramValue!,
            type: paramType!, isMapped: true, mergeIfExist: true);
      }
    }
    overrideParameter(newParamName, paramValue!);
  }

  /// Calls [build] and generates SystemVerilog and a filelist into the
  /// [outputPath], with optional logging sent to the [logger].
  Future<void> buildAndGenerateRTL(
      {Logger? logger, String outputPath = 'output'}) async {
    var synthResults = <SynthesisResult>{};

    // Build
    try {
      await build();
      final synthBuilder = SynthBuilder(this, SystemVerilogSynthesizer());
      synthResults = synthBuilder.synthesisResults;
      final defNames =
          synthResults.map((result) => result.module.definitionName);
      logger
        ?..info('Build Complete...\n')
        ..info('Found ${synthResults.length} hierarchical instances in '
            'design $name')
        ..info('Synth Results: ${defNames.join(', ')}');
    } on Exception catch (e, stackTrace) {
      logger != null
          ? logger.error('Build failed $e, $stackTrace')
          : throw RohdBridgeException('Build failed $e, $stackTrace');
    }

    // Write out RTL
    final outputGenerationPath = '$outputPath/rtl';
    Directory(outputGenerationPath).createSync(recursive: true);

    final filelistContents = StringBuffer();
    logger?.sectionSeparator('Generating RTL');
    final fileIoFutures = <Future<void>>[];
    for (final synthResult in synthResults) {
      final fileName = '${synthResult.module.definitionName}.sv';
      final filePath = '$outputGenerationPath/$fileName';
      filelistContents.writeln('./rtl/$fileName');

      fileIoFutures.add(File(filePath)
          .writeAsString(synthResult.toSynthFileContents().join('\n')));

      logger?.finer('Generated file ${Directory(filePath).absolute.path}');
    }
    await Future.wait(fileIoFutures);

    File('$outputPath/filelist.f')
        .writeAsStringSync(filelistContents.toString());

    logger?.fine('done!');
  }

  /// Adds an interface to this module with comprehensive configuration options.
  ///
  /// This method creates an interface reference within this module, providing a
  /// connection point for interface-based communication. The interface can be
  /// automatically connected to module ports or left unconnected for manual
  /// configuration.
  ///
  /// The [intf] specifies the interface instance to add, [name] provides the
  /// name for the interface reference (subject to uniquification), and [role]
  /// sets the interface role (consumer or provider) determining port
  /// directions. The [connect] controls whether to auto-connect interface ports
  /// via `connectIO`, [allowNameUniquification] determines whether to allow
  /// automatic name resolution, and [portUniquify] provides a custom function
  /// for generating unique port names.
  ///
  /// When [connect] is true, the interface ports are automatically mapped to
  /// module ports using the default naming scheme. When false, port mappings
  /// must be established manually using [addPortMap].
  ///
  /// The [portUniquify] function receives the logical port name and should
  /// return a unique physical port name. If not provided, defaults to
  /// `"${interfaceName}_${logicalPortName}"` format.
  ///
  /// Returns an [InterfaceReference] for accessing interface ports and methods.
  ///
  /// Throws an [Exception] if an interface with the same name already exists.
  InterfaceReference<InterfaceType>
      addInterface<InterfaceType extends PairInterface>(
    InterfaceType intf, {
    required String name,
    required PairRole role,
    bool connect = true,
    bool allowNameUniquification = false,
    String Function(String logical)? portUniquify,
  }) {
    name = _interfaceUniquifier.getUniqueName(
      initialName: name,
      reserved: !allowUniquification || !allowNameUniquification,
    );

    if (_interfaces.containsKey(name)) {
      throw RohdBridgeException('Interface $name already exists in $this');
    }

    final ref = InterfaceReference(name, this, intf, role,
        connect: connect,
        portUniquify: portUniquify ?? (original) => '${name}_$original');

    _interfaces[name] = ref;

    return ref;
  }

  /// Creates a logical alias for an existing port without affecting RTL
  /// generation.
  ///
  /// This method establishes a name mapping that allows [newName] to be used in
  /// place of [currentName] for connections and references. The original port
  /// name remains unchanged in the generated SystemVerilog, but the new name
  /// can be used throughout the ROHD Bridge API.
  ///
  /// The [currentName] must be an existing port name that exists in this
  /// module, and [newName] provides the new alias name to use for the port.
  ///
  /// This is mostly useful for supporting migration from flows that expect
  /// renaming -- usually this is not a good practice.
  ///
  /// Both names become reserved and cannot be reused for other renames. The
  /// port must exist before renaming can be performed.
  ///
  /// Throws an [Exception] if either name has already been used in a rename
  /// operation or the current port name doesn't exist in this module.
  void renamePort(String currentName, String newName) {
    if (_renamedPorts.containsKey(currentName) ||
        _renamedPorts.containsValue(currentName) ||
        _renamedPorts.containsKey(newName) ||
        _renamedPorts.containsValue(newName)) {
      throw RohdBridgeException(
          'Port name $currentName has already been associated with a rename'
          ' and cannot be used again in $name');
    } else {
      if ((tryInput(currentName) == null) &&
          (tryOutput(currentName) == null) &&
          (tryInOut(currentName) == null)) {
        throw RohdBridgeException('Port $currentName does not exist in $name.');
      }
      _renamedPorts[newName] = currentName;
    }
  }

  /// Resolves the current effective name of a port, accounting for renames.
  ///
  /// This internal method returns the name that should be used when referring
  /// to [portName]. If the port has been renamed, it returns the new name;
  /// otherwise, it returns the original name unchanged.
  ///
  /// This ensures consistent name resolution throughout the module's port
  /// management operations.
  String _getRenamedPortName(String portName) {
    if (_renamedPorts.values.contains(portName)) {
      return _renamedPorts.keys
          .firstWhere((key) => _renamedPorts[key] == portName);
    }
    return portName;
  }
}

/// Makes a connection from [driver] to [receiver], punching ports along the way
/// as necessary.
///
/// If [driverPathNewPortName] or [receiverPathNewPortName] are provided, then
/// it will prefer to name new ports with those names. If
/// [allowDriverPathUniquification] or [allowReceiverPathUniquification] are
/// `false`, then the port names will not be uniquified on those paths.
/// Uniquification also respects [BridgeModule.allowUniquification] at each
/// level.
void connectPorts(
  PortReference driver,
  PortReference receiver, {
  String? driverPathNewPortName,
  String? receiverPathNewPortName,
  bool allowDriverPathUniquification = true,
  bool allowReceiverPathUniquification = true,
}) {
  // TODO(mkorbel1): need to add better control over naming of intermediate
  //  ports -- default allow renaming? or should it prefer the top/leaf?

  if (driver.module.hasBuilt || receiver.module.hasBuilt) {
    throw RohdBridgeException('Cannot connect ports after build.');
  }

  final driverInstance = driver.module;
  final receiverInstance = receiver.module;

  BridgeModule? commonParent;

  final driverIsReceiver = driver.module == receiver.module;

  final driverContainsReceiver =
      (driver.module.getHierarchyDownTo(receiver.module) != null) &&
          !driverIsReceiver;

  final receiverContainsDriver =
      (receiver.module.getHierarchyDownTo(driver.module) != null) &&
          !driverIsReceiver;

  if (!driverContainsReceiver &&
      !receiverContainsDriver &&
      driverInstance != receiverInstance &&
      (driver.direction == receiver.direction) &&
      ((driver.direction != PortDirection.inOut) ||
          (receiver.direction != PortDirection.inOut))) {
    // e.g. feed-through
    throw RohdBridgeException(
        'Unhandled directionality and hierarchy of driver and receiver.');
  } else if ((driverContainsReceiver || receiverContainsDriver) &&
      (receiver.direction != driver.direction) &&
      (receiver.direction != PortDirection.inOut &&
          driver.direction != PortDirection.inOut)) {
    final containsStr = driverContainsReceiver
        ? 'driver ${driver.module.name} contains'
            ' receiver ${receiver.module.name}'
        : 'receiver ${receiver.module.name} contains'
            ' driver ${driver.module.name}';

    throw RohdBridgeException(
        'Vertical connections should have the same direction,'
        ' but with $driver driving $receiver, '
        ' $containsStr, but directions are'
        ' ${driver.direction} and ${receiver.direction}, respectively.');
  } else {
    commonParent =
        findCommonParent(driverInstance, receiverInstance) as BridgeModule?;

    if (driverContainsReceiver || receiverContainsDriver) {
      if (receiver.portName == driver.portName) {
        // if we're going up/down and the port names are the same, then we
        // should keep the intermediate name the same
        driverPathNewPortName ??= driver.portName;
        receiverPathNewPortName ??= receiver.portName;
      }
    }
  }
  if (commonParent == null) {
    throw RohdBridgeException('No common parent found between'
        ' $driverInstance and $receiverInstance');
  }

  // start from the driver
  var driverPortRef = driver;

  if (driverInstance != commonParent) {
    // we need to punch upwards from the driver to the common parent

    final driverPath = commonParent.getHierarchyDownTo(driverInstance)!;

    for (var i = driverPath.length - 2; i >= 1; i--) {
      final driverPathI = driverPath[i] as BridgeModule;
      final uniqName = driverPathI._getUniquePortName(
        driverPortRef,
        initialName: driverPathNewPortName,
        allowNameUniquification: allowDriverPathUniquification,
      );

      driverPortRef = driverPortRef.punchUpTo(
        driverPathI,
        newPortName: uniqName,
      );
    }
  }

  // now start from the receiver, pulling up
  var receiverPortRef = receiver;

  // keep track of all created receiver ports so far so we can update
  // the corresponding modules' [_upperSourceMap]s
  final createdReceiverPorts = <PortReference>[];

  if (receiverInstance != commonParent) {
    // we need to punch upwards from the receiver to the common parent

    final receiverPath = commonParent.getHierarchyDownTo(receiverInstance)!;

    for (var i = receiverPath.length - 2; i >= 1; i--) {
      // find if there are ports that are already connected to the driver from
      // anywhere up the chain
      final upperTargets = TraverseableCollection<PortReference>()
        ..add(driverPortRef);
      // TODO(mkorbel1): is there a more efficient way to do this search? can
      //  something be cached efficiently?

      final receiverPathI = receiverPath[i] as BridgeModule;

      for (var upperTargIdx = 0;
          upperTargIdx < upperTargets.length;
          upperTargIdx++) {
        final upperTarg = upperTargets[upperTargIdx];
        final upperTargTargs = receiverPath
            .getRange(1, i + 1)
            .map((receiverPathMod) =>
                (receiverPathMod as BridgeModule)._upperSourceMap[upperTarg])
            .nonNulls;

        for (final iterUpperTargi in upperTargTargs) {
          if (receiverPathI._upperSourceMap.containsKey(iterUpperTargi)) {
            // if we already have a known connection up to the driver from
            // here, then we can just connect to the existing port and exit
            // immediately
            receiverPortRef
                .gets(receiverPathI._upperSourceMap[iterUpperTargi]!);
            return;
          }

          upperTargets.add(iterUpperTargi);
        }
      }

      final uniqName = receiverPathI._getUniquePortName(
        receiverPortRef,
        initialName: receiverPathNewPortName,
        allowNameUniquification: allowReceiverPathUniquification,
      );

      receiverPortRef =
          receiverPortRef.punchUpTo(receiverPathI, newPortName: uniqName);

      createdReceiverPorts.add(receiverPortRef);

      // now we tell all prior-created ports that they can access the current
      // receiver port via the port that was created.
      for (final createdReceiverPort in createdReceiverPorts) {
        final receiverPortModule = createdReceiverPort.module;
        assert(!receiverPortModule._upperSourceMap.containsKey(receiverPortRef),
            'should not be recreating a path if one already exists.');
        receiverPortModule._upperSourceMap[receiverPortRef] =
            createdReceiverPort;
      }
    }
  }

  // also notify about the top-level driver
  for (final createdReceiverPort in [receiver, ...createdReceiverPorts]) {
    final receiverPortModule = createdReceiverPort.module;

    receiverPortModule._upperSourceMap[driverPortRef] = createdReceiverPort;
  }

  receiverPortRef.gets(driverPortRef);
}

/// Connects [intf1] to [intf2], creating all necessary ports through the
/// hierarchy.
///
/// If [intf1PathNewName] or [intf2PathNewName] are provided, then it will
/// prefer to name new interfaces with those names. If
/// [allowIntf1PathUniquification] or [allowIntf2PathUniquification] are
/// `false`, then the interface names will not be uniquified on those paths.
/// Uniquification also respects [BridgeModule.allowUniquification] at each
/// level. The [exceptPorts] parameter is an optional set of strings
/// representing the logical port names to be excluded.
void connectInterfaces(
  InterfaceReference intf1,
  InterfaceReference intf2, {
  String? intf1PathNewName,
  String? intf2PathNewName,
  bool allowIntf1PathUniquification = true,
  bool allowIntf2PathUniquification = true,
  Set<String>? exceptPorts,
  // TODO(mkorbel): finish these,
  //  possibly wont be needed for connectInterfaces
  //  String Function(String logical, String? physical)? portUniquify1,
  //  String Function(String logical, String? physical)? portUniquify2,
}) {
  if (intf1.module.hasBuilt || intf2.module.hasBuilt) {
    throw RohdBridgeException('Cannot connect interfaces after build.');
  }

  final intf1Instance = intf1.module;
  final intf2Instance = intf2.module;

  if (intf1.role != intf2.role) {
    // up and down case
    final commonParent = findCommonParent(intf1Instance, intf2Instance);

    if (commonParent == intf1Instance || commonParent == intf2Instance) {
      throw RohdBridgeException(
          'Vertical connections should have the same role, but the common'
          ' parent of $intf1Instance and $intf2Instance is $commonParent,'
          ' but with mismatched roles ${intf1.role} and ${intf2.role},'
          ' respectively.');
    }

    if (commonParent == null) {
      throw RohdBridgeException('No common parent found between'
          ' $intf1Instance and $intf2Instance');
    }
    final unusedPortsOnDriver = intf1.getUnmappedInterfacePorts();
    final unusedPortOnReceiver = intf2.getUnmappedInterfacePorts();
    if (exceptPorts != null && exceptPorts.isNotEmpty) {
      unusedPortsOnDriver.removeWhere(exceptPorts.contains);
      unusedPortOnReceiver.removeWhere(exceptPorts.contains);
    }

    if (unusedPortsOnDriver.isNotEmpty || unusedPortOnReceiver.isNotEmpty) {
      var errorString = 'Cannot connect interface ${intf1.name} '
          'at ${intf1Instance.name} to interface '
          '${intf2.name} at ${intf2Instance.name} '
          'because there are unmapped ports';
      if (unusedPortsOnDriver.isNotEmpty) {
        errorString += ' : $unusedPortsOnDriver on driver';
      }
      if (unusedPortOnReceiver.isNotEmpty) {
        errorString += ' : $unusedPortOnReceiver on receiver';
      }
      throw RohdBridgeException(errorString);
    }
    final intf1Top =
        (commonParent.getHierarchyDownTo(intf1Instance)![1] as BridgeModule)
            .pullUpInterface(
      intf1,
      newIntfName: intf1PathNewName,
      allowIntfUniquification: allowIntf1PathUniquification,
      exceptPorts: exceptPorts,
    );
    final intf2Top =
        (commonParent.getHierarchyDownTo(intf2Instance)![1] as BridgeModule)
            .pullUpInterface(
      intf2,
      newIntfName: intf2PathNewName,
      allowIntfUniquification: allowIntf2PathUniquification,
      exceptPorts: exceptPorts,
    );

    intf1Top.connectTo(intf2Top, exceptPorts: exceptPorts);
  } else if (intf1.role == intf2.role) {
    final intf1ToIntf2Path = intf1Instance.getHierarchyDownTo(intf2Instance);
    final intf2ToIntf1Path = intf2Instance.getHierarchyDownTo(intf1Instance);

    final intf1ContainsIntf2 = intf1ToIntf2Path != null;
    final intf2ContainsIntf1 = intf2ToIntf1Path != null;

    if (intf1ContainsIntf2) {
      intf1.module._pullUpInterfaceAndConnect(
        intf2,
        newIntfName: intf2PathNewName,
        allowIntfUniquification: allowIntf2PathUniquification,
        topToConnect: intf1,
        exceptPorts: exceptPorts,
      );
    } else if (intf2ContainsIntf1) {
      intf2.module._pullUpInterfaceAndConnect(
        intf1,
        newIntfName: intf1PathNewName,
        allowIntfUniquification: allowIntf1PathUniquification,
        topToConnect: intf2,
        exceptPorts: exceptPorts,
      );
    } else {
      // e.g. feed-through
      throw RohdBridgeException(
          'Unhandled directionality and hierarchy of driver and receiver.');
    }
  } else {
    throw RohdBridgeException(
        'Unknown directionality and hierarchy of driver and receiver.');
  }
}
