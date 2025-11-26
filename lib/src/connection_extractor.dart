// Copyright (C) 2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// connection_extractor.dart
// Extracts connection information from a set of modules.
//
// 2025 June
// Author: Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:rohd_bridge/src/references/reference.dart';

class ConstReference extends Reference {
  final LogicValue value;

  ConstReference(this.value) : super(null);

  @override
  String toString() => 'Const($value)';
}

/// Represents a connection between two [Reference]s.
@immutable
abstract class Connection<RefType extends Reference> {
  /// The first point of the connection.
  final RefType point1;

  /// The second point of the connection.
  final RefType point2;

  /// Creates a new [Connection] between two [RefType] points.
  const Connection(this.point1, this.point2);

  /// Indicates whether [point] is one of the points in this connection.
  bool hasPoint(RefType point) => point1 == point || point2 == point;

  /// Indicates whether this connection involves the given [module] on either of
  /// its points.
  bool involvesModule(BridgeModule module) =>
      point1.module == module || point2.module == module;

  /// Returns the point in this connection that corresponds to the given
  /// [module], or `null` if this does not [involvesModule].
  RefType? pointForModule(BridgeModule module) {
    if (point1.module == module) {
      return point1;
    } else if (point2.module == module) {
      return point2;
    } else {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is Connection<RefType> &&
      other.hasPoint(point1) &&
      other.hasPoint(point2);

  @override
  int get hashCode => point1.hashCode ^ point2.hashCode;
}

/// A connection between two [InterfaceReference]s.
@immutable
class InterfaceConnection extends Connection<InterfaceReference> {
  /// Creates a new [InterfaceConnection] between two [InterfaceReference]s.
  const InterfaceConnection(super.point1, super.point2);

  @override
  String toString() => '${point1.module.name}.$point1 <==> '
      '${point2.module.name}.$point2';
}

mixin PortDrivenConnection<ReferenceType extends Reference>
    on Connection<ReferenceType> {
  PortReference get dst;
}

class TieOffConnection extends Connection<Reference> with PortDrivenConnection {
  /// Creates a new [TieOffConnection] between a [PortReference] and a
  /// [ConstReference].
  const TieOffConnection(
      ConstReference super.point1, PortReference super.point2);

  PortReference get dst => point2 as PortReference;

  @override
  String toString() => '$point1 x--> '
      '${point2.module!.name}.$point2';
}

/// A connection between two [PortReference]s or [ConstReference]s.
@immutable
class AdHocConnection extends Connection<PortReference>
    with PortDrivenConnection {
  /// The source driver port of the connection.
  PortReference get src {
    final p1ContainsP2 =
        point1.module.getHierarchyDownTo(point2.module) != null;
    final p2ContainsP1 =
        point2.module.getHierarchyDownTo(point1.module) != null;

    if (p1ContainsP2) {
      if (point1.direction == PortDirection.output) {
        return point2;
      } else {
        return point1;
      }
    } else if (p2ContainsP1) {
      if (point2.direction == PortDirection.output) {
        return point1;
      } else {
        return point2;
      }
    }

    return point1.direction == PortDirection.output ? point1 : point2;
  }

  /// The destination load port of the connection.
  PortReference get dst => src == point1 ? point2 : point1;

  /// Indicates whether this connection is a net connection (i.e., both
  /// [PortReference]s are [LogicNet]s).
  bool get isNet => src.port.isNet && dst.port.isNet;

  /// Creates a new [AdHocConnection] between two [PortReference]s.
  const AdHocConnection(super.point1, super.point2);

  String get _connectorString => isNet ? '<-->' : '--->';

  @override
  String toString() => '${src.module.name}.$src $_connectorString '
      '${dst.module.name}.$dst';

  /// Takes a collection of [AdHocConnection]s and simplifies them by merging
  /// connections that are between the same ports in adjacent ranges.
  static List<AdHocConnection> _simplify(List<AdHocConnection> complex) =>
      // TODO(mkorbel1): implement simplification of connections
      complex;
}

/// A structure for tracking slicing information during tracing.
@immutable
class _ConnectionSliceTracking {
  /// The current source.
  final Logic src;

  /// The original destination.
  final Logic dst;

  /// The current low index of the [src].
  final int srcLowIndex;

  /// The current high index of the [src].
  final int srcHighIndex;

  /// The current low index of the [dst].
  final int dstLowIndex;

  /// The current high index of the [dst].
  final int dstHighIndex;

  /// The dimension access for the destination, if applicable.
  final List<int> dstDimensionAccess;

  /// The module of the [src].
  BridgeModule get srcModule => src.parentModule! as BridgeModule;

  /// The module of the [dst].
  BridgeModule get dstModule => dst.parentModule! as BridgeModule;

  /// Converts the [src] to a [PortReference].
  Reference toSrcRef() => src is Const
      ? ConstReference(src.value)
      : PortReference.fromPort(src).slice(srcHighIndex, srcLowIndex);

  /// Converts the [dst] to a [PortReference].
  PortReference toDstRef() =>
      PortReference.fromPort(dst).slice(dstHighIndex, dstLowIndex);

  /// The width of the tracking currently.
  int get width => srcHighIndex - srcLowIndex + 1;

  /// Nets can connect to themselves, but if its identical, then it's useless.
  bool isSelfConnection() =>
      src == dst &&
      srcLowIndex == dstLowIndex &&
      srcHighIndex == dstHighIndex &&
      const ListEquality<int>().equals(dstDimensionAccess, const []);

  /// Creates a new [_ConnectionSliceTracking] instance.
  _ConnectionSliceTracking({
    required this.src,
    required this.srcLowIndex,
    required this.srcHighIndex,
    required this.dst,
    required this.dstLowIndex,
    required this.dstHighIndex,
    required List<int> dstDimensionAccess,
  })  : dstDimensionAccess = List.unmodifiable(dstDimensionAccess),
        assert(srcHighIndex - srcLowIndex == dstHighIndex - dstLowIndex,
            'Widths should match between source and destination ranges.'),
        assert(
            srcLowIndex >= 0 &&
                srcHighIndex < src.width &&
                dstLowIndex >= 0 &&
                dstHighIndex < dst.width,
            'Indices must be within the bounds of the'
            ' source and destination Logic.');

  /// Creates a copy of this [_ConnectionSliceTracking] with new values for some
  /// fields.
  _ConnectionSliceTracking copyWith({
    Logic? src,
    int? srcLowIndex,
    int? srcHighIndex,
    Logic? dst,
    int? dstLowIndex,
    int? dstHighIndex,
    List<int>? dstDimensionAccess,
  }) =>
      _ConnectionSliceTracking(
        src: src ?? this.src,
        srcLowIndex: srcLowIndex ?? this.srcLowIndex,
        srcHighIndex: srcHighIndex ?? this.srcHighIndex,
        dst: dst ?? this.dst,
        dstLowIndex: dstLowIndex ?? this.dstLowIndex,
        dstHighIndex: dstHighIndex ?? this.dstHighIndex,
        dstDimensionAccess: dstDimensionAccess ?? this.dstDimensionAccess,
      );

  @override
  String toString() => '${src.name}[$srcHighIndex:$srcLowIndex] --> '
      '${dst.name}[$dstHighIndex:$dstLowIndex]';

  @override
  bool operator ==(Object other) =>
      other is _ConnectionSliceTracking &&
      other.src == src &&
      other.srcLowIndex == srcLowIndex &&
      other.srcHighIndex == srcHighIndex &&
      other.dst == dst &&
      other.dstLowIndex == dstLowIndex &&
      other.dstHighIndex == dstHighIndex &&
      const ListEquality<int>()
          .equals(other.dstDimensionAccess, dstDimensionAccess);

  @override
  int get hashCode =>
      src.hashCode ^
      srcLowIndex.hashCode ^
      srcHighIndex.hashCode ^
      dst.hashCode ^
      dstLowIndex.hashCode ^
      dstHighIndex.hashCode ^
      const ListEquality<int>().hash(dstDimensionAccess);
}

/// Analyzes a set of modules and provides connection information between them.
class ConnectionExtractor {
  /// All the connections between [modules], without tracing through any of the
  /// boundaries of [modules].
  ///
  /// Note that this only calculates at the time of construction of this
  /// extractor, so if the modules change, you will need to create a new
  /// extractor to get the updated connections.
  Set<Connection> get connections => UnmodifiableSetView(_connections);
  final Set<Connection> _connections = {};

  /// The set of modules to analyze for connections.
  final Set<BridgeModule> modules;

  /// If `true`, then the extracted [connections] will include
  /// [InterfaceConnection]s. Set this to `false` if you want only ad-hoc
  /// connections (and tie-offs).
  final bool includeInterfaceConnections;

  /// Creates a new [ConnectionExtractor] for the given [modules] which will
  /// then identify [connections] between them.
  ConnectionExtractor(Iterable<BridgeModule> modules,
      {this.includeInterfaceConnections = true})
      : modules = Set.unmodifiable(modules) {
    // algorithm:
    //  - first, find all full interface-to-interface connections
    //  - then, the remainder can be ad-hoc
    if (includeInterfaceConnections) {
      _findInterfaceConnections();
    }
    _findAdHocConnections();
  }

  /// Finds all [InterfaceConnection]s between the [modules].
  void _findInterfaceConnections() {
    for (final module in modules) {
      for (final intf in module.interfaces.values) {
        if (!intf.isFullyConnected) {
          continue;
        }

        if (intf.ports
            .where((p) =>
                p.direction == PortDirection.input ||
                p.direction == PortDirection.inOut)
            .isEmpty) {
          continue; // skip if no input ports
        }

        if (intf.interface.getPorts([PairDirection.sharedInputs]).isNotEmpty) {
          continue; // skip if there are shared inputs, can't be fully connected
        }

        // find all the InterfaceReferences connected to *any* ports of this one
        final modulesConnectedToIntf = <BridgeModule>{};

        for (final intfPort in intf.ports) {
          final portsOnMod = intf.portMaps
              .where((e) => e.interfacePort == intfPort)
              .map((e) => e.port);

          final connectedMappingsFromElsewhere =
              portsOnMod.map((e) => _traceDriverForMappings(e.port)).flattened;

          modulesConnectedToIntf.addAll(
            connectedMappingsFromElsewhere.map((portRef) => portRef.srcModule),
          );
        }

        for (final otherModule in modulesConnectedToIntf) {
          for (final otherIntf in otherModule.interfaces.values) {
            if (otherIntf == intf) {
              continue; // don't connect to self
            }

            if (!otherIntf.isFullyConnected) {
              continue; // skip if not fully connected
            }

            if (otherIntf.interface
                .getPorts([PairDirection.sharedInputs]).isNotEmpty) {
              continue; // skip if there are shared inputs
            }

            if (connections.contains(InterfaceConnection(intf, otherIntf))) {
              continue; // already connected
            }

            // check if *every* port of otherIntf is connected FULLY to intf
            // and in both directions
            final allOtherIntfInpsDriven = otherIntf.ports
                .where((p) =>
                    p.direction == PortDirection.input ||
                    p.direction == PortDirection.inOut)
                .every((otherPort) {
              final otherPortMappings = otherIntf.portMaps
                  .where((e) => e.interfacePort == otherPort)
                  .map((e) => _traceDriverForMappings(e.port.port))
                  .flattened;

              return otherPortMappings.any(
                (mapping) =>
                    mapping.srcModule == module &&
                    mapping.srcModule.interfaces.values.any(
                      (testIntf) =>
                          testIntf == intf &&
                          testIntf.portMaps.any((pm) =>
                              pm.isConnected && pm.port == mapping.toSrcRef()),
                    ),
              );
            });

            final allThisIntfInpsDriven = intf.ports
                .where((p) =>
                    p.direction == PortDirection.input ||
                    p.direction == PortDirection.inOut)
                .every((thisPort) {
              final thisPortMappings = intf.portMaps
                  .where((e) => e.interfacePort == thisPort)
                  .map((e) => _traceDriverForMappings(e.port.port))
                  .flattened;

              return thisPortMappings.any(
                (mapping) =>
                    mapping.srcModule == otherModule &&
                    mapping.srcModule.interfaces.values.any(
                      (testIntf) =>
                          testIntf == otherIntf &&
                          testIntf.portMaps.any((pm) =>
                              pm.isConnected && pm.port == mapping.toSrcRef()),
                    ),
              );
            });

            if (allOtherIntfInpsDriven && allThisIntfInpsDriven) {
              _connections.add(InterfaceConnection(intf, otherIntf));
            }
          }
        }
      }
    }
  }

  /// Finds all [AdHocConnection]s between the [modules].
  void _findAdHocConnections() {
    final adHocConnections = <AdHocConnection>[];
    final tieOffConnections = <TieOffConnection>[];
    for (final module in modules) {
      for (final port in [
        ...module.inputs.values,
        ...module.inOuts.values,
        ...module.outputs.values,
      ]) {
        final mappings = _traceDriverForMappings(port);

        for (final mapping in mappings) {
          final srcRef = mapping.toSrcRef();
          final dstRef = mapping.toDstRef();

          final thisModIsIntfConn = connections
              .whereType<InterfaceConnection>()
              .map((e) => e.pointForModule(module))
              .nonNulls
              .any((intfRef) => intfRef.portMaps.any(
                    (pm) => pm.port == dstRef,
                  ));

          final otherModule = srcRef.module;
          final otherModIsIntfConn = otherModule != null &&
              connections
                  .whereType<InterfaceConnection>()
                  .map((e) => e.pointForModule(otherModule))
                  .nonNulls
                  .any((intfRef) => intfRef.portMaps.any(
                        (pm) => pm.port == srcRef,
                      ));

          if (thisModIsIntfConn && otherModIsIntfConn) {
            // if both modules are already connected via an interface, skip
            continue;
          }

          switch (srcRef) {
            case ConstReference():
              tieOffConnections.add(TieOffConnection(srcRef, dstRef));
            case PortReference():
              adHocConnections.add(AdHocConnection(srcRef, dstRef));
            default:
              throw RohdBridgeException(
                  'Invalid source reference type $srcRef');
          }
        }
      }
    }

    _connections
      ..addAll(
        AdHocConnection._simplify(adHocConnections),
      )
      ..addAll(tieOffConnections);
  }

  /// Follows backwards from a [load], assumed to be an input or inOut port (or
  /// an interface port directly connected to one) of a module within [modules],
  /// and returns a list of [PortReference]s that drive it.
  ///
  /// Does not continue to recurse through modules that are in [modules].
  ///
  /// If a module is found which specifies more than just connectivity and
  /// hierarchy, it will be a dead end (e.g. if there's non-trivial logic
  /// driving the signal).
  List<_ConnectionSliceTracking> _traceDriverForMappings(Logic load) {
    assert(load.isPort, 'load must be a port, got $load');

    if (load is LogicArray) {
      // need to drop down into each element
      return [
        for (final element in load.elements) ..._traceDriverForMappings(element)
      ];
    } else {
      return _traceDriverForSources(
        _ConnectionSliceTracking(
            dst: load,
            src: load,
            srcLowIndex: 0,
            srcHighIndex: load.width - 1,
            dstLowIndex: 0,
            dstHighIndex: load.width - 1,
            dstDimensionAccess: const []),
      ).whereNot((e) => e.isSelfConnection()).toList();
    }
  }

  /// A trace cache for memoization and to avoid infinite recursion for nets.
  ///
  /// A value of `null` indicates that the tracking is in progress.
  final Map<_ConnectionSliceTracking, List<_ConnectionSliceTracking>?> _cache =
      {};

  /// Follows backwards from a [loadTracking] and returns a list of
  /// [_ConnectionSliceTracking]s representing the connections to drive it.
  List<_ConnectionSliceTracking> _traceDriverForSources(
      _ConnectionSliceTracking loadTracking) {
    // check if we've already computed this tracking
    if (_cache.containsKey(loadTracking)) {
      if (_cache[loadTracking] == null) {
        // in progress, return empty list, nothing more to find
        return const [];
      } else {
        return _cache[loadTracking]!;
      }
    }

    // mark as in progress
    _cache[loadTracking] = null;

    final foundTrackings = <_ConnectionSliceTracking>[];

    for (final src in [
      ...loadTracking.src.srcConnections,
    ]) {
      foundTrackings.addAll(
        _analyzeSrc(
          src,
          loadTracking: loadTracking,
          handleSwizzle: (handleSwizzle, swizzleInputs, swizzleOutput) =>
              _applyConcatenation(
            loadTracking,
            components: swizzleInputs,
          ),
          handleBusSubset: (handleBusSubset, busOrigInput, busSubsetOutput,
                  startIndex, endIndex) =>
              [
            _applySubset(
              loadTracking,
              startIndex: startIndex,
              endIndex: endIndex,
              superSet: busOrigInput,
            )
          ],
        ),
      );
    }

    // now for nets, we need to do some additional search behavior in the other
    // direction
    if (loadTracking.src.isNet) {
      for (final src in [
        ...loadTracking.src.dstConnections.where((e) => e.isNet),
      ]) {
        foundTrackings.addAll(
          _analyzeSrc(src, loadTracking: loadTracking,
              handleSwizzle: (loadTracking, swizzleInputs, swizzleOutput) {
            if (src == swizzleOutput) {
              // this is the normal direction
              return _applyConcatenation(
                loadTracking,
                components: swizzleInputs,
              );
            }

            // we're going backwards, so this looks like a busSubset sort of,
            // but we need to deduce the index
            var startIndex = 0;
            assert(swizzleInputs.contains(src),
                'Swizzle inputs must contain the source, got $swizzleInputs');
            for (final swizIn in swizzleInputs) {
              if (swizIn == src) {
                break;
              }
              startIndex += swizIn.width;
            }
            final endIndex = startIndex + loadTracking.width - 1;

            return [
              _applySubset(
                loadTracking,
                startIndex: startIndex,
                endIndex: endIndex,
                superSet: swizzleOutput,
              )
            ];
          }, handleBusSubset: (loadTracking, busOrigInput, busSubsetOutput,
                  startIndex, endIndex) {
            if (src == busSubsetOutput) {
              // this is the normal direction
              return [
                _applySubset(
                  loadTracking,
                  startIndex: startIndex,
                  endIndex: endIndex,
                  superSet: busOrigInput,
                )
              ];
            }

            // we're going backwards, so this sort of looks like a simpler
            // version of a swizzle
            return _applyConcatenation(
              loadTracking,
              components: [
                Logic(name: 'DUMMY_LOW', width: startIndex),
                busSubsetOutput,
                Logic(
                    name: 'DUMMY_HIGH',
                    width: busOrigInput.width - endIndex - 1),
              ].where((e) => e.width > 0).toList(),
            );
          }),
        );
      }
    }

    // cache the result to save performance
    final finalTrackings =
        List<_ConnectionSliceTracking>.unmodifiable(foundTrackings);
    _cache[loadTracking] = finalTrackings;

    return finalTrackings;
  }

  /// Helper function for [_traceDriverForSources] to analyze a source
  /// [Logic] and return a list of [_ConnectionSliceTracking]s.
  List<_ConnectionSliceTracking> _analyzeSrc(
    Logic src, {
    required _ConnectionSliceTracking loadTracking,
    required List<_ConnectionSliceTracking> Function(
            _ConnectionSliceTracking loadTracking,
            List<Logic> swizzleInputs,
            Logic swizzleOutput)
        handleSwizzle,
    required List<_ConnectionSliceTracking> Function(
            _ConnectionSliceTracking loadTracking,
            Logic busOrigInput,
            Logic busSubsetOutput,
            int startIndex,
            int endIndex)
        handleBusSubset,
  }) {
    final foundTrackings = <_ConnectionSliceTracking>[];

    if (src is Const) {
      foundTrackings.add(loadTracking.copyWith(src: src));
      return foundTrackings;
    }

    if (src.isPort) {
      final srcMod = src.parentModule!;
      if (modules.contains(srcMod)) {
        foundTrackings.add(loadTracking.copyWith(src: src));
        if (srcMod != loadTracking.dstModule) {
          return foundTrackings;
        }
      } else if (srcMod is Swizzle) {
        // TODO(mkorbel1): eventually, use named ports here and for BusSubset
        //  too (https://github.com/intel/rohd/issues/609)

        final swizzleInputs = [...srcMod.inputs.values, ...srcMod.inOuts.values]
            .where((e) => e.name != srcMod.resultSignalName)
            .toList();

        final swizzleOutput = srcMod.tryOutput(srcMod.resultSignalName) ??
            srcMod.inOut(srcMod.resultSignalName);

        final newTrackings = handleSwizzle(
          loadTracking,
          swizzleInputs,
          swizzleOutput,
        );

        for (final newTracking in newTrackings) {
          foundTrackings.addAll(
            _traceDriverForSources(newTracking),
          );
        }

        return foundTrackings;
      } else if (srcMod is BusSubset) {
        final busOrigInput = [...srcMod.inputs.values, ...srcMod.inOuts.values]
            .where((e) => e.name != srcMod.resultSignalName)
            .first;
        final busSubsetOutput = srcMod.tryOutput(srcMod.resultSignalName) ??
            srcMod.inOut(srcMod.resultSignalName);

        final newTrackings = handleBusSubset(
          loadTracking,
          busOrigInput,
          busSubsetOutput,
          srcMod.startIndex,
          srcMod.endIndex,
        );

        for (final newTracking in newTrackings) {
          foundTrackings.addAll(
            _traceDriverForSources(newTracking),
          );
        }

        return foundTrackings;
      }
    }

    // if we're not skipping, we can continue tracing
    foundTrackings.addAll(_traceDriverForSources(
      loadTracking.copyWith(src: src),
    ));

    return foundTrackings;
  }

  /// Applies a subset of the [loadTracking] to the [superSet].
  static _ConnectionSliceTracking _applySubset(
      _ConnectionSliceTracking loadTracking,
      {required int startIndex,
      required int endIndex,
      required Logic superSet}) {
    final newSrcLowIdx = startIndex + loadTracking.srcLowIndex;
    final newSrcHighIdx = newSrcLowIdx + (loadTracking.width - 1);

    return loadTracking.copyWith(
      src: superSet,
      srcLowIndex: newSrcLowIdx,
      srcHighIndex: newSrcHighIdx,
    );
  }

  /// Applies a concatenation of the [loadTracking] to the [components].
  static List<_ConnectionSliceTracking> _applyConcatenation(
    _ConnectionSliceTracking loadTracking, {
    required List<Logic> components,
  }) {
    final foundTrackings = <_ConnectionSliceTracking>[];

    // we need to identify which portions of the dst overlap with which
    // portions of the collection of swizzle inputs, then split the
    // tracking into multiple on a per-dest-subset basis

    var swizzleIdx = 0;
    var swizzleBitIdx = 0;

    // first, slide up the swizzleIdx until we get to the src we want
    var srcIdx = 0;
    while (srcIdx < loadTracking.srcLowIndex) {
      swizzleBitIdx++;
      srcIdx++;

      if (swizzleBitIdx >= components[swizzleIdx].width) {
        // move to the next swizzle input
        swizzleIdx++;
        swizzleBitIdx = 0;
      }
    }

    assert(swizzleIdx < components.length,
        'swizzleIdx should be within bounds of swizzleInputs');

    int? currNewDstHighIndex;
    int? currNewDstLowIndex;
    int? currSwizzleInputHighIndex;
    int? currSwizzleInputLowIndex = swizzleBitIdx;

    void checkAndFlushCurrentTracking() {
      assert(swizzleIdx < components.length,
          'swizzleIdx should be within bounds of swizzleInputs');

      final hitSwizzleInputEnd =
          swizzleBitIdx >= components[swizzleIdx].width - 1;

      final hitDstRangeEnd = currNewDstHighIndex != null &&
          currNewDstHighIndex! >= loadTracking.dstHighIndex;

      if (hitSwizzleInputEnd || hitDstRangeEnd) {
        if (currNewDstHighIndex != null && currNewDstLowIndex != null) {
          final currSwizzleInput = components[swizzleIdx];

          final newLoadTracking = loadTracking.copyWith(
            src: currSwizzleInput,
            srcLowIndex: currSwizzleInputLowIndex,
            srcHighIndex: currSwizzleInputHighIndex,
            dstLowIndex: currNewDstLowIndex,
            dstHighIndex: currNewDstHighIndex,
          );

          foundTrackings.add(newLoadTracking);

          // move to the next swizzle input
          swizzleIdx++;
          swizzleBitIdx = -1; // negative since we incr to 0 next!
          currSwizzleInputLowIndex = null;
          currSwizzleInputHighIndex = null;

          // reset the current dst indices
          currNewDstLowIndex = null;
          currNewDstHighIndex = null;
        }
      }
    }

    for (var dstIdx = loadTracking.dstLowIndex;
        dstIdx <= loadTracking.dstHighIndex;
        dstIdx++, swizzleBitIdx++) {
      currSwizzleInputLowIndex ??= 0;
      currSwizzleInputHighIndex = currSwizzleInputHighIndex == null
          ? currSwizzleInputLowIndex
          : currSwizzleInputHighIndex! + 1;

      currNewDstLowIndex ??= dstIdx;
      currNewDstHighIndex =
          currNewDstHighIndex == null ? dstIdx : currNewDstHighIndex! + 1;

      checkAndFlushCurrentTracking();
    }

    assert(foundTrackings.isNotEmpty,
        'No found trackings, this should not happen.');

    return foundTrackings;
  }
}
