// Copyright (C) 2024-2025 Intel Corporation
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

/// An enumeration of the possible relative locations of two ports' modules.
enum _RelativePortLocation {
  thisAboveOther,
  otherAboveThis,
  sameLevel,
  sameModule,
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

  PortReference._(super.module, this.portName);

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
  /// The [port] must be a port of a [BridgeModule]. If the [port] is an array
  /// member, this will create a [PortReference] that includes the appropriate
  /// array indexing to access that specific element.
  factory PortReference.fromPort(Logic port) {
    if (!port.isPort) {
      throw RohdBridgeException('$port is not a port');
    }

    final dimAccesses = <String>[];
    while (port.isArrayMember) {
      dimAccesses.add('[${port.arrayIndex!}]');
      port = port.parentStructure!;
    }

    return PortReference.fromString(port.parentModule! as BridgeModule,
        port.name + dimAccesses.reversed.join());
  }

  @override
  String toString() => portName;

  /// Connects this port to be driven by [other].
  ///
  /// This establishes a connection where the signal from [other] drives this
  /// port. The connection respects the hierarchical nature of the modules and
  /// handles directionality of ports appropriately.
  void gets(PortReference other) {
    final relativeLocation = _relativeLocationOf(other);

    if (relativeLocation == _RelativePortLocation.sameModule &&
        (other is InterfacePortReference || this is InterfacePortReference)) {
      throw RohdBridgeException(
          'Connections involving interface ports on the same module'
          ' ${module.name} should be done using port maps.');
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

    getsInternal(other);
  }

  /// Implementation of [gets] after some validation.
  @internal
  void getsInternal(PortReference other);

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

  /// Creates a slice of this port from [endIndex] down to [startIndex].
  ///
  /// Both indices are inclusive. For example, `slice(7, 0)` would create a
  /// reference to bits 7 through 0 of the port.
  PortReference slice(int endIndex, int startIndex);

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
  ({Logic receiver, Logic driver}) _relativeReceiverAndDriver(
      PortReference other) {
    final loc = _relativeLocationOf(other);

    switch (loc) {
      case _RelativePortLocation.sameModule:
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
                return (receiver: _externalPort, driver: other._externalPort);
              } else {
                // this is the internal side connection
                return (receiver: _internalPort, driver: other._internalPort);
              }
            case PortDirection.output:
              if (other is InterfacePortReference) {
                // this is the internal side connection
                return (receiver: _internalPort, driver: other._internalPort);
              } else {
                // this is the external side connection
                return (receiver: _externalPort, driver: other._externalPort);
              }
          }
        }

        if (direction == PortDirection.input &&
            other.direction == PortDirection.output) {
          // loop-back
          return (driver: other._externalPort, receiver: _externalPort);
        } else {
          return (driver: other._internalPort, receiver: _internalPort);
        }

      case _RelativePortLocation.sameLevel:
        return (driver: other._externalPort, receiver: _externalPort);
      case _RelativePortLocation.thisAboveOther:
        return (driver: other._externalPort, receiver: _internalPort);
      case _RelativePortLocation.otherAboveThis:
        return (driver: other._internalPort, receiver: _externalPort);
    }
  }

  /// The driver subset considering the relative hierarchy of the ports.
  ///
  /// It is assumed that [other] is driving `this` (part of a call to [gets]).
  dynamic _relativeDriverSubset(PortReference other) {
    final loc = _relativeLocationOf(other);

    switch (loc) {
      case _RelativePortLocation.sameModule:
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
  void tieOff([dynamic value = 0]) {
    getsLogic(Const(value, width: width));
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
