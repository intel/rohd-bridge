// Copyright (C) 2024-2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_reference.dart
// Definitions for accessing ports.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

part of 'references.dart';

/// The type of connection to make between two ports or interfaces on the same
/// module.
///
/// When connecting ports or interfaces on the same [BridgeModule], the
/// connection can either be a [loopback] (external, pin-to-pin) or a
/// [passthrough] (internal, net-to-net).
///
/// For most direction combinations, the connection type is unambiguous and
/// [PortReference.gets] can infer it automatically. However, when at least one
/// port is [PortDirection.inOut] and neither port is [PortDirection.input], the
/// connection type must be explicitly specified via [PortReference.gets] or
/// [connectPorts]. Interface connections can select the type via
/// [InterfaceReference.connectTo] or [connectInterfaces].
enum SameModuleConnectionType {
  /// An external (loopback) connection between ports on the same module.
  ///
  /// This connects the external-facing sides of the ports, making the
  /// connection visible outside the module.
  loopback,

  /// An internal (passthrough) connection between ports on the same module.
  ///
  /// This connects the internal-facing sides of the ports, making the
  /// connection visible only within the module.
  passthrough,
}

/// An enumeration of the possible relative locations of two ports' modules.
enum _RelativePortLocation {
  /// This reference belongs to the parent of the other reference's module.
  thisAboveOther,

  /// The other reference belongs to the parent of this reference's module.
  otherAboveThis,

  /// The references belong to distinct modules with the same parent.
  sameLevel,

  /// Both references belong to the same module.
  sameModule,
}

/// Identifies an endpoint and requested name for intermediate signal reuse.
///
/// `port` is the physical root port, while `side` is its resolved internal or
/// external signal. `lower` and `upper` are inclusive flattened bit offsets.
/// `arrayRank` distinguishes whole arrays from subarrays covering the same
/// bits. `isInternal` separates internal and external connection scopes even
/// when both sides use the same signal object, as with output ports.
typedef _IntermediateEndpoint = ({
  Logic port,
  Logic side,
  int lower,
  int upper,
  int arrayRank,
  String name,
  bool isInternal,
});

/// Named intermediates recorded for endpoints on a single [BridgeModule].
///
/// Only Bridge-created signals are indexed; existing connections are not
/// searched for manually created signals with matching names.
/// Multiple candidates preserve existing connections when a stricter naming
/// request requires a separate alias.
class _IntermediateSignals {
  /// Connected source candidates, even after a failed receiver attempt.
  final drivers = <_IntermediateEndpoint, Set<Logic>>{};

  /// Completed receiver connections indexed for repeats and net fan-in reuse.
  final receivers = <_IntermediateEndpoint, Set<Logic>>{};
}

/// A [Reference] to a port on a [BridgeModule].
///
/// This abstract class provides a unified interface for accessing and
/// manipulating ports on a [BridgeModule], including support for port slicing,
/// connections, and hierarchical port punching operations.
@immutable
sealed class PortReference extends Reference {
  /// The name of the port that this reference points to.
  final String portName;

  /// The actual [Logic] port that this reference points to.
  ///
  /// This will resolve to the input, output, or inOut port with [portName] on
  /// the [module]. Throws an exception if the port is not found.
  late final Logic port = module.tryInput(portName) ??
      module.tryOutput(portName) ??
      module.tryInOut(portName) ??
      (throw RohdBridgeException('Port $portName not found in $module'));

  /// The direction of the port (input, output, or inOut).
  late final PortDirection direction = PortDirection.ofPort(port);

  /// Creates a reference to [portName] on the given module.
  PortReference._(super.module, this.portName);

  /// Validates that this reference resolves to an existing port and subset.
  @override
  void validate() => portSubset;

  /// Creates a [PortReference] from a [BridgeModule] and a port reference
  /// string.
  ///
  /// The [portRef] string can be either a simple port name (e.g., "myPort") or
  /// include slicing/indexing (e.g., "myPort[3:0]", "myPort[5]").
  ///
  /// Returns either a [StandardPortReference] for simple names or a
  /// [SlicePortReference] for complex port access patterns.
  factory PortReference.fromString(BridgeModule module, String portRef) {
    if (SlicePortReference._isSliceAccess(portRef)) {
      return SlicePortReference.fromString(module, portRef);
    }

    if (StandardPortReference._isStandardAccess(portRef)) {
      return StandardPortReference(module, portRef);
    }

    throw RohdBridgeException('Invalid port access string: $portRef');
  }

  /// Creates a [PortReference] from an existing [Logic] port.
  ///
  /// The [port] must be a port of a [BridgeModule]. For members of a structured
  /// port, this creates a reference to the corresponding packed range or array
  /// element of the physical root port.
  factory PortReference.fromPort(Logic port) {
    if (!port.isPort) {
      throw RohdBridgeException('$port is not a port');
    }

    var rootPort = port;
    while (rootPort.parentStructure != null) {
      rootPort = rootPort.parentStructure!;
    }

    bool isRootArrayDimension(LogicStructure structure) {
      LogicStructure? ancestor = structure;
      while (ancestor != null) {
        if (ancestor is! LogicArray) {
          return false;
        }
        ancestor = ancestor.parentStructure;
      }
      return true;
    }

    final dimensionAccesses = <int>[];
    var packedLowIndex = 0;
    var currentPort = port;
    while (currentPort.parentStructure != null) {
      final parent = currentPort.parentStructure!;

      if (isRootArrayDimension(parent)) {
        dimensionAccesses.add(currentPort.arrayIndex!);
      } else {
        for (final sibling in parent.elements) {
          if (identical(sibling, currentPort)) {
            break;
          }
          packedLowIndex += sibling.width;
        }
      }

      currentPort = parent;
    }

    final reference = PortReference.fromString(
      rootPort.parentModule! as BridgeModule,
      rootPort.name +
          dimensionAccesses.reversed.map((index) => '[$index]').join(),
    );

    if (packedLowIndex == 0 && port.width == reference.width) {
      return reference;
    }

    return reference.slice(
      packedLowIndex + port.width - 1,
      packedLowIndex,
    );
  }

  @override
  String toString() => portName;

  /// Connects this port to be driven by [other].
  ///
  /// This establishes a connection where the signal from [other] drives this
  /// port. The connection respects the hierarchical nature of the modules and
  /// handles directionality of ports appropriately.
  ///
  /// When connecting two ports on the same module where the connection type is
  /// ambiguous (at least one port is [PortDirection.inOut] and neither is
  /// [PortDirection.input]), a [sameModuleConnectionType] must be provided to
  /// disambiguate.
  ///
  /// If [intermediateSignalName] is provided, an intermediate signal with that
  /// name is inserted on sibling-level and same-module connections. See
  /// [_insertIntermediateSignalIfNeeded] for details on when the name is
  /// applied and when it is silently ignored.
  ///
  /// Set [allowIntermediateSignalNameUniquification] to `false` to reserve the
  /// exact name. Incompatible reserved-name collisions fail during synthesis.
  /// This has no effect when no intermediate name is applied. An incompatible
  /// cached intermediate is left intact; new fan-out receivers and net fan-in
  /// can use a separate strict alias. Replacing an already-connected non-net
  /// receiver's intermediate or using an unsupported custom clone throws
  /// [RohdBridgeException]. See [connectPorts] for aggregate restrictions.
  void gets(PortReference other,
      {SameModuleConnectionType? sameModuleConnectionType,
      String? intermediateSignalName,
      bool allowIntermediateSignalNameUniquification = true}) {
    final relativeLocation = _relativeLocationOf(other);

    if (relativeLocation == _RelativePortLocation.sameModule) {
      _validateSameModuleInterfacePortMap();
      other._validateSameModuleInterfacePortMap();

      if (_isMappedTo(other) || other._isMappedTo(this)) {
        _connectSameModuleInterfacePortMaps();
        other._connectSameModuleInterfacePortMaps();
        return;
      }

      if (sameModuleConnectionType == null &&
          (_requiresExplicitSameModuleConnectionType ||
              other._requiresExplicitSameModuleConnectionType)) {
        throw RohdBridgeException(
            'Same-module connections involving interface ports require an '
            'explicit SameModuleConnectionType.');
      }
    }

    if (relativeLocation == _RelativePortLocation.sameLevel &&
        direction == other.direction &&
        (direction != PortDirection.inOut)) {
      throw RohdBridgeException(
          'Cannot connect two ports with the same direction'
          ' on sibling modules.');
    }

    if (relativeLocation == _RelativePortLocation.thisAboveOther &&
        direction == PortDirection.input &&
        other.direction == PortDirection.input) {
      throw RohdBridgeException(
          'A submodule (${other.module}) input ($other) cannot drive a parent '
          'module ($module) input ($this).');
    }

    if (relativeLocation == _RelativePortLocation.otherAboveThis &&
        direction == PortDirection.output &&
        other.direction == PortDirection.output) {
      throw RohdBridgeException(
          'A parent module (${other.module}) output ($other) cannot drive a '
          'submodule ($module) output ($this).');
    }

    if (direction == PortDirection.output &&
        other.direction == PortDirection.input &&
        relativeLocation != _RelativePortLocation.sameModule) {
      throw RohdBridgeException(
          'Cannot use an input $other from ${other.module}'
          ' to drive $this, an output of $module.');
    }

    if (relativeLocation == _RelativePortLocation.sameModule &&
        direction == PortDirection.input &&
        other.direction == PortDirection.input) {
      throw RohdBridgeException(
          'An input port $other on module ${other.module} cannot drive an'
          ' input $this on the same module');
    }

    if (relativeLocation == _RelativePortLocation.otherAboveThis &&
        direction == PortDirection.input &&
        other.direction == PortDirection.output) {
      throw RohdBridgeException(
          'A parent module (${other.module}) output ($other) cannot drive a '
          'submodule ($module) input ($this).');
    }

    if (relativeLocation == _RelativePortLocation.thisAboveOther &&
        direction == PortDirection.input &&
        other.direction == PortDirection.output) {
      throw RohdBridgeException(
          'A submodule (${other.module}) output ($other) cannot drive a '
          'parent module ($module) input ($this).');
    }

    if (relativeLocation != _RelativePortLocation.sameModule &&
        sameModuleConnectionType != null) {
      throw RohdBridgeException(
          'SameModuleConnectionType should only be provided when connecting'
          ' ports on the same module, but $this is on $module'
          ' and $other is on ${other.module}.');
    }

    // Same-module connection type validation
    var resolvedConnectionType = sameModuleConnectionType;
    if (relativeLocation == _RelativePortLocation.sameModule) {
      resolvedConnectionType =
          _validateSameModuleConnectionType(other, sameModuleConnectionType);

      _connectSameModuleInterfacePortMaps();
      other._connectSameModuleInterfacePortMaps();
    }

    _connectOverlappingInterfacePortMaps();
    other._connectOverlappingInterfacePortMaps();

    getsInternal(other,
        sameModuleConnectionType: resolvedConnectionType,
        intermediateSignalName: intermediateSignalName,
        allowIntermediateSignalNameUniquification:
            allowIntermediateSignalNameUniquification);
  }

  /// Validates and resolves the [SameModuleConnectionType] for a same-module
  /// connection.
  ///
  /// Returns the resolved [SameModuleConnectionType] to use for the connection,
  /// or `null` if it doesn't matter.
  ///
  /// Throws if the connection is ambiguous and no type is specified, or if the
  /// specified type conflicts with the forced connection type for the given
  /// direction combination.
  SameModuleConnectionType? _validateSameModuleConnectionType(
      PortReference other, SameModuleConnectionType? provided) {
    // Determine if the connection is ambiguous:
    // At least one port is inOut and neither is input.
    final isAmbiguous = (direction == PortDirection.inOut ||
            other.direction == PortDirection.inOut) &&
        direction != PortDirection.input &&
        other.direction != PortDirection.input;

    if (isAmbiguous) {
      if (provided == null) {
        throw RohdBridgeException('Connecting ${other.direction.name} $other to'
            ' ${direction.name} $this on the same module (${module.name})'
            ' is ambiguous.'
            ' Provide a SameModuleConnectionType'
            ' (loopback or passthrough) to disambiguate.');
      }

      // output←inOut with loopback is invalid: output ports cannot be driven
      // by external inOut sources.
      if (direction == PortDirection.output &&
          other.direction == PortDirection.inOut &&
          provided == SameModuleConnectionType.loopback) {
        throw RohdBridgeException(
            'SameModuleConnectionType.loopback is not valid for'
            ' output←inOut on the same module.'
            ' An output port cannot be driven by the external side of an'
            ' inOut port. Use passthrough instead.');
      }

      return provided;
    }

    // Non-ambiguous cases: determine the forced type.
    SameModuleConnectionType? forcedType;

    if (direction == PortDirection.input) {
      // input receiver → always loopback (external)
      forcedType = SameModuleConnectionType.loopback;
    } else if (direction == PortDirection.output &&
        other.direction == PortDirection.input) {
      // output←input → always passthrough (internal)
      forcedType = SameModuleConnectionType.passthrough;
    } else if (direction == PortDirection.inOut &&
        other.direction == PortDirection.input) {
      // inOut←input → always passthrough (internal)
      forcedType = SameModuleConnectionType.passthrough;
    }
    // output←output → equivalent, no forced type

    // If a type was provided, validate it matches the forced type.
    if (provided != null && forcedType != null && provided != forcedType) {
      throw RohdBridgeException(
          'SameModuleConnectionType.${provided.name} is not valid for'
          ' ${direction.name}←${other.direction.name} on the same module.'
          ' Must be ${forcedType.name}.');
    }

    return provided ?? forcedType;
  }

  /// Implementation of [gets] after some validation.
  ///
  /// The [intermediateSignalName], if provided, is forwarded to
  /// [_insertIntermediateSignalIfNeeded] so that a named intermediate signal
  /// can be inserted on sibling-level or same-module connections.
  @internal
  void getsInternal(PortReference other,
      {SameModuleConnectionType? sameModuleConnectionType,
      String? intermediateSignalName,
      bool allowIntermediateSignalNameUniquification = true});

  /// Inserts or reuses a named intermediate for sibling or same-module
  /// connections, returning [driverValue] as the driver when none is needed.
  /// The `alreadyConnected` result skips assignment on repeated connections.
  /// Call `onConnected`, if provided, after successfully assigning the driver.
  ///
  /// Preserves aggregate shape and custom clone types; bit selections use
  /// packed signals. Setting [allowIntermediateSignalNameUniquification] to
  /// `false` requires reserved emitted names. See [gets] for restrictions.
  ///
  /// Reuses only Bridge-created intermediates, matching endpoints and requested
  /// names for fan-out and compatible bidirectional fan-in.
  ///
  /// [driverRoot] and [receiverRoot] are the resolved port-side signals before
  /// slicing. [isInternal] keeps internal and external connections separate.
  ({
    dynamic driver,
    bool alreadyConnected,
    void Function()? onConnected
  }) _insertIntermediateSignalIfNeeded(
      dynamic driverValue, String? intermediateSignalName, PortReference other,
      {required Logic driverRoot,
      required Logic receiverRoot,
      required bool isInternal,
      required bool allowIntermediateSignalNameUniquification}) {
    final relativeLocation = _relativeLocationOf(other);
    final supportsIntermediateSignal =
        relativeLocation == _RelativePortLocation.sameLevel ||
            relativeLocation == _RelativePortLocation.sameModule;

    if (intermediateSignalName == null || !supportsIntermediateSignal) {
      return (driver: driverValue, alreadyConnected: false, onConnected: null);
    }

    final driverSlice =
        driverValue is List<Logic> && other is SlicePortReference
            ? other
            : null;
    if (driverValue is! Logic && driverSlice?.subsetDimensions == null) {
      return (driver: driverValue, alreadyConnected: false, onConnected: null);
    }

    final naming = allowIntermediateSignalNameUniquification
        ? Naming.renameable
        : Naming.reserved;
    Naming.validatedName(intermediateSignalName,
        reserveName: !allowIntermediateSignalNameUniquification);

    final driverRegistry =
        _intermediateSignals[other.module] ??= _IntermediateSignals();
    final receiverRegistry =
        _intermediateSignals[module] ??= _IntermediateSignals();
    final driverKey = other._intermediateEndpoint(
        driverRoot, intermediateSignalName,
        isInternal: isInternal);
    final receiverKey = _intermediateEndpoint(
        receiverRoot, intermediateSignalName,
        isInternal: isInternal);

    /// Whether [signal] satisfies the requested naming policy for reuse.
    bool matchesName(Logic signal) =>
        allowIntermediateSignalNameUniquification ||
        (signal.name == intermediateSignalName &&
            _hasReservedIntermediateNames(signal));

    /// Rejects unsupported custom clones before connecting or recording.
    void validateName(Logic signal) {
      if (!matchesName(signal)) {
        throw RohdBridgeException(
            'Intermediate signal $intermediateSignalName must retain its exact '
            'name and reserve its emitted names, including the structure name '
            'prefix on fields. The custom clone does not support strict '
            'naming.');
      }
    }

    /// Records an available driver candidate and defers receiver registration.
    ///
    /// A failed receiver assignment must not hide an already-connected driver
    /// candidate, nor may it be treated as a completed connection on retry.
    ({Logic driver, bool alreadyConnected, void Function()? onConnected})
        connection(Logic signal, {bool alreadyConnected = false}) {
      (driverRegistry.drivers[driverKey] ??= {}).add(signal);
      return (
        driver: signal,
        alreadyConnected: alreadyConnected,
        onConnected: alreadyConnected
            ? null
            : () {
                (receiverRegistry.receivers[receiverKey] ??= {}).add(signal);
              },
      );
    }

    final driverSignals =
        driverValue is Logic ? [driverValue] : driverValue as List<Logic>;
    final existingDriverNets = driverRegistry.drivers[driverKey] ?? <Logic>{};
    final existingReceiverNets =
        receiverRegistry.receivers[receiverKey] ?? <Logic>{};
    final sharedNets = existingDriverNets.where(existingReceiverNets.contains);
    for (final existingNet in sharedNets) {
      if (matchesName(existingNet)) {
        return connection(existingNet, alreadyConnected: true);
      }
    }
    if (sharedNets.any((signal) => !signal.isNet)) {
      throw RohdBridgeException(
          'Cannot replace the existing intermediate $intermediateSignalName '
          'on an already-connected non-net receiver with a strict alias.');
    }

    for (final existingNet in existingDriverNets) {
      if (matchesName(existingNet)) {
        return connection(existingNet);
      }
    }

    for (final existingReceiverNet in existingReceiverNets) {
      if (matchesName(existingReceiverNet) &&
          existingReceiverNet.isNet &&
          driverSignals.every((signal) => signal.isNet) &&
          (driverValue is Logic
              ? _sameIntermediateShape(existingReceiverNet, driverValue)
              : existingReceiverNet is LogicArray &&
                  const ListEquality<int>().equals(
                      existingReceiverNet.dimensions,
                      driverSlice!.subsetDimensions) &&
                  existingReceiverNet.elementWidth ==
                      driverSlice.subsetElementWidth &&
                  existingReceiverNet.numUnpackedDimensions ==
                      driverSlice.subsetNumUnpackedDimensions)) {
        if (driverValue is Logic) {
          existingReceiverNet <= driverValue;
        } else {
          existingReceiverNet.assignSubset(driverSignals);
        }
        return connection(existingReceiverNet);
      }
    }

    if (driverSlice != null) {
      final arrayBuilder =
          driverSignals.any((signal) => signal.isNet) || port.isNet
              ? LogicArray.net
              : LogicArray.new;
      return connection(arrayBuilder(
          driverSlice.subsetDimensions!, driverSlice.subsetElementWidth,
          numUnpackedDimensions: driverSlice.subsetNumUnpackedDimensions!,
          name: intermediateSignalName,
          naming: naming)
        ..assignSubset(driverSignals));
    }

    final driver = driverValue as Logic;
    final Logic net;
    if (driver is LogicArray && driver.runtimeType == LogicArray) {
      final arrayBuilder = driver.isNet ? LogicArray.net : LogicArray.new;
      net = arrayBuilder(driver.dimensions, driver.elementWidth,
          numUnpackedDimensions: driver.numUnpackedDimensions,
          name: intermediateSignalName,
          naming: naming);
    } else {
      net = driver is LogicStructure
          ? driver.clone(name: intermediateSignalName)
          : (driver.isNet || port.isNet)
              ? LogicNet(
                  name: intermediateSignalName,
                  width: driver.width,
                  naming: naming)
              : Logic(
                  name: intermediateSignalName,
                  width: driver.width,
                  naming: naming);
    }
    validateName(net);
    net <= driver;
    return connection(net);
  }

  /// Whether every independently emitted name in [signal] is reserved.
  ///
  /// Strict naming requires a reserved array declaration name. Non-array
  /// structures emit their fields separately and must explicitly reserve names
  /// prefixed with [structureName], since ROHD emits reserved names literally.
  static bool _hasReservedIntermediateNames(Logic signal,
          {String? structureName}) =>
      signal is LogicStructure && signal is! LogicArray
          ? signal.elements.isNotEmpty &&
              signal.elements.every((field) => _hasReservedIntermediateNames(
                  field,
                  structureName: structureName ?? signal.name))
          : signal.naming == Naming.reserved &&
              (structureName == null ||
                  signal.name.startsWith('${structureName}_'));

  /// Registries weakly associated with their endpoint modules.
  ///
  /// The [Expando] does not keep a module alive solely to retain its registry.
  static final _intermediateSignals = Expando<_IntermediateSignals>();

  /// Builds a key from this reference's normalized selection and port [side].
  ///
  /// Equivalent reference objects share a key, while different [name] requests,
  /// array ranks, and [isInternal] scopes remain distinct.
  _IntermediateEndpoint _intermediateEndpoint(Logic side, String name,
      {required bool isInternal}) {
    final reference = this;
    final arrayRank = reference is SlicePortReference
        ? reference.subsetDimensions?.length ?? 0
        : port is LogicArray
            ? (port as LogicArray).dimensions.length
            : 0;
    return (
      port: port,
      side: side,
      lower: _flatRange.lower,
      upper: _flatRange.upper,
      arrayRank: arrayRank,
      name: name,
      isInternal: isInternal,
    );
  }

  /// Whether two signals have compatible representations for fan-in reuse.
  ///
  /// Arrays must match dimensions, element width, and packed/unpacked layout.
  /// Other structures must match concrete type and recursive element shapes.
  /// Scalar signals need only match width; net eligibility is checked by the
  /// caller, and signal names and existing connections are not compared here.
  static bool _sameIntermediateShape(Logic first, Logic second) {
    if (first.width != second.width) {
      return false;
    }
    if (first is LogicArray && second is LogicArray) {
      return const ListEquality<int>()
              .equals(first.dimensions, second.dimensions) &&
          first.elementWidth == second.elementWidth &&
          first.numUnpackedDimensions == second.numUnpackedDimensions;
    }
    if (first is LogicStructure || second is LogicStructure) {
      return first is LogicStructure &&
          second is LogicStructure &&
          first.runtimeType == second.runtimeType &&
          first.elements.length == second.elements.length &&
          Iterable<int>.generate(first.elements.length).every((index) =>
              _sameIntermediateShape(
                  first.elements[index], second.elements[index]));
    }
    return true;
  }

  /// Connects this port to be driven by a [Logic] [other].
  ///
  /// This is a direct connection where the [Logic] signal drives this
  /// reference. Prefer to use [gets] or other higher-level connection methods
  /// when possible.
  void getsLogic(Logic other);

  /// Drives a [Logic] [other] with this port.
  ///
  /// This directly connects the [other] signal to be driven by this reference.
  /// Prefer to use [gets] or other higher-level connection methods when
  /// possible.
  void drivesLogic(Logic other);

  /// Verifies that this reference has a recorded port map when it represents
  /// an interface port in a same-module connection.
  void _validateSameModuleInterfacePortMap() {}

  /// Activates port maps relevant to this reference when it represents an
  /// interface port in a same-module connection.
  void _connectSameModuleInterfacePortMaps() {}

  /// Whether this reference is an interface port mapped directly to [other].
  bool _isMappedTo(PortReference other) => false;

  /// Whether this reference requires an explicit connection type for a
  /// same-module connection.
  bool get _requiresExplicitSameModuleConnectionType => false;

  /// Creates a slice of this port from [endIndex] down to [startIndex].
  ///
  /// Both indices are inclusive. For example, `slice(7, 0)` would create a
  /// reference to bits 7 through 0 of the port.
  PortReference slice(int endIndex, int startIndex);

  /// The inclusive bit range of this reference within the flattened port.
  ///
  /// This is used to compare standard and sliced references that point into
  /// the same base port.
  ({int lower, int upper}) get _flatRange;

  /// Whether this reference and [other] select any common bits of the same
  /// port on the same module.
  bool _overlaps(PortReference other) {
    if (module != other.module || portName != other.portName) {
      return false;
    }

    final thisRange = _flatRange;
    final otherRange = other._flatRange;

    return thisRange.lower <= otherRange.upper &&
        otherRange.lower <= thisRange.upper;
  }

  /// Activates any deferred port maps that should be resolved before this
  /// reference is used as a concrete port operation endpoint.
  void _connectOverlappingInterfacePortMaps() {}

  /// Gets a single bit of this port at the specified [index].
  ///
  /// This is equivalent to calling `slice(index, index)`.
  PortReference operator [](int index) => slice(index, index);

  /// The port subset that this reference represents.
  ///
  /// Returns either a [Logic] signal or a [List<Logic>] that can be used for
  /// driving connections. The exact type depends on whether this is a simple
  /// port reference or a complex sliced reference.
  ///
  /// For input or inOut ports, the returned value should only be used to drive
  /// logic within the [module]. For output ports, it can be used to drive logic
  /// either within or outside of the [module].
  dynamic get portSubset;

  /// The internal port used for connections within the module.
  ///
  /// This may have side-effects like introducing new internal interfaces on
  /// [InterfaceReference].
  Logic get _internalPort => switch (direction) {
        PortDirection.input => module.input(portName),
        PortDirection.output => module.output(portName),
        PortDirection.inOut => module.inOut(portName),
      };

  /// The external port used for connections outside the module.
  Logic get _externalPort => switch (direction) {
        PortDirection.input => module.inputSource(portName),
        PortDirection.output => module.output(portName),
        PortDirection.inOut => module.inOutSource(portName),
      };

  /// The internal port subset used for connections within the module.
  dynamic get _internalPortSubset;

  /// The external port subset used for connections outside the module.
  dynamic get _externalPortSubset;

  /// Determines the relative position of the [other]s module to this [module].
  ///
  /// Assumes that the two ports are in the same hierarchy or one is the parent
  /// of the other.
  _RelativePortLocation _relativeLocationOf(PortReference other) {
    if (module == other.module) {
      return _RelativePortLocation.sameModule;
    } else if (module.parent == other.module.parent) {
      return _RelativePortLocation.sameLevel;
    } else if (module == other.module.parent) {
      return _RelativePortLocation.thisAboveOther;
    } else if (other.module == module.parent) {
      return _RelativePortLocation.otherAboveThis;
    } else {
      throw RohdBridgeException(
          'Could not determine relative placement of inout ports.');
    }
  }

  /// The receiver and driver considering the relative hierarchy of the ports.
  ///
  /// It is assumed that [other] is driving `this` (part of a call to [gets]).
  ///
  /// The returned `isInternal` flag identifies same-module connections using
  /// internal-facing ports. Intermediate naming is disabled for vertical
  /// connections, for which this flag is `false`.
  ///
  /// When [sameModuleConnectionType] is provided for same-module connections,
  /// it overrides the default internal/external port selection.
  ({Logic receiver, Logic driver, bool isInternal}) _relativeReceiverAndDriver(
      PortReference other,
      {SameModuleConnectionType? sameModuleConnectionType}) {
    final loc = _relativeLocationOf(other);

    switch (loc) {
      case _RelativePortLocation.sameModule:
        // When an explicit connection type is provided, use it directly.
        if (sameModuleConnectionType == SameModuleConnectionType.loopback) {
          return (
            driver: other._externalPort,
            receiver: _externalPort,
            isInternal: false
          );
        } else if (sameModuleConnectionType ==
            SameModuleConnectionType.passthrough) {
          return (
            driver: other._internalPort,
            receiver: _internalPort,
            isInternal: true
          );
        }

        final includesOneIntfPortRef =
            [this, other].whereType<InterfacePortReference>().length == 1;

        // special handling for interface port reference connections
        if (includesOneIntfPortRef) {
          final portDir =
              this is! InterfacePortReference ? direction : other.direction;

          switch (portDir) {
            case PortDirection.input || PortDirection.inOut:
              if (other is InterfacePortReference) {
                // this is the external side connection
                return (
                  receiver: _externalPort,
                  driver: other._externalPort,
                  isInternal: false
                );
              } else {
                // this is the internal side connection
                return (
                  receiver: _internalPort,
                  driver: other._internalPort,
                  isInternal: true
                );
              }
            case PortDirection.output:
              if (other is InterfacePortReference) {
                // this is the internal side connection
                return (
                  receiver: _internalPort,
                  driver: other._internalPort,
                  isInternal: true
                );
              } else {
                // this is the external side connection
                return (
                  receiver: _externalPort,
                  driver: other._externalPort,
                  isInternal: false
                );
              }
          }
        }

        if (direction == PortDirection.input &&
            other.direction == PortDirection.output) {
          // loop-back
          return (
            driver: other._externalPort,
            receiver: _externalPort,
            isInternal: false
          );
        } else {
          return (
            driver: other._internalPort,
            receiver: _internalPort,
            isInternal: true
          );
        }

      case _RelativePortLocation.sameLevel:
        return (
          driver: other._externalPort,
          receiver: _externalPort,
          isInternal: false
        );
      case _RelativePortLocation.thisAboveOther:
        return (
          driver: other._externalPort,
          receiver: _internalPort,
          isInternal: false
        );
      case _RelativePortLocation.otherAboveThis:
        return (
          driver: other._internalPort,
          receiver: _externalPort,
          isInternal: false
        );
    }
  }

  /// The driver subset considering the relative hierarchy of the ports.
  ///
  /// It is assumed that [other] is driving `this` (part of a call to [gets]).
  ///
  /// When [sameModuleConnectionType] is provided for same-module connections,
  /// it overrides the default internal/external port selection.
  dynamic _relativeDriverSubset(PortReference other,
      {SameModuleConnectionType? sameModuleConnectionType}) {
    final loc = _relativeLocationOf(other);

    switch (loc) {
      case _RelativePortLocation.sameModule:
        // When an explicit connection type is provided, use it directly.
        if (sameModuleConnectionType == SameModuleConnectionType.loopback) {
          return other._externalPortSubset;
        } else if (sameModuleConnectionType ==
            SameModuleConnectionType.passthrough) {
          return other._internalPortSubset;
        }

        final includesOneIntfPortRef =
            [this, other].whereType<InterfacePortReference>().length == 1;

        // special handling for interface port reference connections
        if (includesOneIntfPortRef) {
          final portDir =
              this is! InterfacePortReference ? direction : other.direction;

          switch (portDir) {
            case PortDirection.input || PortDirection.inOut:
              if (other is InterfacePortReference) {
                // this is the external side connection
                return other._externalPortSubset;
              } else {
                // this is the internal side connection
                return other._internalPortSubset;
              }
            case PortDirection.output:
              if (other is InterfacePortReference) {
                // this is the internal side connection
                return other._internalPortSubset;
              } else {
                // this is the external side connection
                return other._externalPortSubset;
              }
          }
        }

        if (direction == PortDirection.input &&
            other.direction == PortDirection.output) {
          // loop-back
          return other._externalPortSubset;
        } else {
          return other._internalPortSubset;
        }

      case _RelativePortLocation.sameLevel:
        return other._externalPortSubset;
      case _RelativePortLocation.thisAboveOther:
        return other._externalPortSubset;
      case _RelativePortLocation.otherAboveThis:
        return other._internalPortSubset;
    }
  }

  /// Ties this port to a constant [value].
  ///
  /// The [value] can be any type that can be used to construct a [Const], such
  /// as an integer, boolean, or [LogicValue]. If no value is provided, the port
  /// will be tied to 0.
  void tieOff({dynamic value = 0, bool fill = false}) {
    _connectOverlappingInterfacePortMaps();

    getsLogic(module.tieOffConst(value, width: width, fill: fill));
  }

  /// The bit width of this port reference.
  late final int width = portSubsetLogic.width;

  /// A [Logic] representation of the port subset.
  ///
  /// If [portSubset] returns a [Logic], this returns it directly. If it returns
  /// a [List<Logic>], this concatenates them using `rswizzle()`.
  ///
  /// For input or inOut ports, this should only be used to drive logic within
  /// the [module]. For output ports, it can be used to drive logic either
  /// within or outside of the [module].
  late final portSubsetLogic = portSubset is Logic
      ? portSubset as Logic
      : (portSubset as List<Logic>).rswizzle();

  /// Creates a matching port in the parent module and connects them.
  ///
  /// This "punches up" the port to [parentModule], creating a port with the
  /// same direction and optionally renaming it to [newPortName]. The new port
  /// is automatically connected to this port.
  ///
  /// Throws an exception if [parentModule] is not actually a parent of this
  /// port's [module].
  PortReference punchUpTo(BridgeModule parentModule, {String? newPortName}) {
    if (parentModule.getHierarchyDownTo(module) == null) {
      throw RohdBridgeException(
          'Cannot punch up to a module that is not a parent.');
    }

    _connectOverlappingInterfacePortMaps();

    if (!parentModule.subModules.contains(module)) {
      return parentModule.pullUpPort(this, newPortName: newPortName);
    }

    // make a new port in the same direction on new module
    final newPortRef =
        replicateTo(parentModule, direction, newPortName: newPortName);

    if (direction == PortDirection.output) {
      newPortRef.gets(this);
    } else {
      gets(newPortRef);
    }
    return newPortRef;
  }

  /// Creates a matching port in a submodule and connects them.
  ///
  /// This "punches down" the port to [subModule], creating a port with the same
  /// direction and optionally renaming it to [newPortName]. The new port is
  /// automatically connected to this port.
  ///
  /// Throws an exception if [subModule] is not actually a submodule of this
  /// port's [module].
  PortReference punchDownTo(BridgeModule subModule, {String? newPortName}) {
    if (module.getHierarchyDownTo(subModule) == null) {
      throw RohdBridgeException(
          'Cannot punch down to a module that is not a submodule.');
    }

    _connectOverlappingInterfacePortMaps();

    // make a new port in the same direction on new module
    final newPortRef =
        replicateTo(subModule, direction, newPortName: newPortName);

    if (!module.subModules.contains(subModule)) {
      if (direction == PortDirection.output) {
        connectPorts(newPortRef, this);
      } else {
        connectPorts(this, newPortRef);
      }

      return newPortRef;
    }

    if (direction == PortDirection.output) {
      gets(newPortRef);
    } else {
      newPortRef.gets(this);
    }

    return newPortRef;
  }

  /// Creates a new port in the specified module with the given direction.
  ///
  /// This creates a port in [newModule] with the specified [direction] and
  /// optionally renames it to [newPortName]. The new port will have the same
  /// width and array dimensions as this port reference.
  ///
  /// If this is a sliced reference, only the subset dimensions are replicated.
  PortReference replicateTo(BridgeModule newModule, PortDirection direction,
      {String? newPortName});

  @override
  bool operator ==(Object other) =>
      other is PortReference &&
      other.port == port &&
      other.module == module &&
      other.toString() == toString();

  @override
  int get hashCode => port.hashCode ^ module.hashCode ^ toString().hashCode;
}
