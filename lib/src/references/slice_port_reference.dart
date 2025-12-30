// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// slice_port_reference.dart
// Definitions for accessing ports with slices.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

part of 'references.dart';

/// A [PortReference] that provides access to sliced or indexed portions of a
/// port.
///
/// This class handles complex port access patterns including bit-level slicing
/// and multi-dimensional array indexing. It supports various access patterns
/// while ensuring type safety and proper connection semantics.
@immutable
class SlicePortReference extends PortReference {
  /// Regular expression pattern for valid slice access strings.
  ///
  /// Supports the following access patterns:
  /// ```text
  /// myPort[0]         -- single element access
  /// myPort[1:0]       -- bit slice access
  /// myPort[3][1]      -- multi-dimensional array access
  /// myPort[3][2:1]    -- multi-dimensional access with bit slice
  /// myPort[5][4][3:2] -- deep multi-dimensional access with slice
  /// ```
  ///
  /// Note: Bit slicing (using `:`) is only supported on the final dimension.
  static final RegExp _sliceAccessRegex =
      RegExp(r'^([a-zA-Z0-9_]+)(\[\d+\])*(\[\d+:\d+\])?$');

  /// Regular expression for extracting bracketed index/slice expressions.
  static final RegExp _bracketedAreas = RegExp(r'\[([\d:]+)\]');

  /// Checks if a port access string contains slicing or indexing syntax.
  ///
  /// Returns `true` if [portAccessString] contains bracket notation, indicating
  /// it's a slice or index access rather than a simple port name.
  static bool _isSliceAccess(String portAccessString) =>
      _sliceAccessRegex.hasMatch(portAccessString) &&
      portAccessString.contains('[');

  /// Array dimension and/or bit indices for multi-dimensional array access.
  ///
  /// Contains the index values for each array dimension that is being accessed,
  /// and/or the bit slice at the end. `null` if this is not an array access.
  late final List<int>? dimensionAccess;

  /// The upper bound of the slice (inclusive).
  ///
  /// For slice access like `[7:0]`, this would be `7`. `null` if this is not a
  /// slice access.
  late final int? sliceUpperIndex;

  /// The lower bound of the slice (inclusive).
  ///
  /// For slice access like `[7:0]`, this would be `0`. `null` if this is not a
  /// slice access.
  late final int? sliceLowerIndex;

  /// The width of the slice in element count (bits or elements).
  ///
  /// Only applicable when [hasSlicing] is `true`. Represents the number of bits
  /// included in the slice (upper - lower + 1).
  late final int? _sliceCount =
      !hasSlicing ? null : (sliceUpperIndex! - sliceLowerIndex! + 1);

  /// Whether this reference includes slicing.
  ///
  /// Returns `true` if both [sliceUpperIndex] and [sliceLowerIndex] are
  /// defined, indicating this is a slice like `[7:0]` rather than just an array
  /// index like `[3]`.
  bool get hasSlicing => sliceUpperIndex != null && sliceLowerIndex != null;

  /// Creates a slice port reference with the specified parameters.
  ///
  /// The [dimensionAccess] list contains indices for multi-dimensional array
  /// access, while [sliceUpperIndex] and [sliceLowerIndex] define slicing. Both
  /// slice indices must be provided together or both must be null.
  ///
  /// The constructor automatically optimizes certain patterns:
  /// - Single-bit slices like `[3:3]` become array access `[3]`
  /// - Full-width slices that match array dimensions are simplified
  SlicePortReference(super.module, super.portName,
      {List<int>? dimensionAccess, int? sliceUpperIndex, int? sliceLowerIndex})
      : super._() {
    if ((sliceUpperIndex == null) != (sliceLowerIndex == null)) {
      throw RohdBridgeException(
          'Both or neither slice indices must be provided');
    }

    if (sliceUpperIndex == sliceLowerIndex && sliceUpperIndex != null) {
      // if we have something like [3:3], just convert to [3]
      this.dimensionAccess = [
        if (dimensionAccess != null) ...dimensionAccess,
        sliceUpperIndex
      ];
      this.sliceUpperIndex = null;
      this.sliceLowerIndex = null;
    } else if (port is LogicArray &&
        sliceLowerIndex == 0 &&
        sliceUpperIndex != null &&
        (dimensionAccess == null ||
            dimensionAccess.length < (port as LogicArray).dimensions.length) &&
        sliceUpperIndex ==
            (port as LogicArray).dimensions[(dimensionAccess?.length ?? 0)] -
                1) {
      // if we have something like [7:0] on an array at the end, but it's still
      // referring to a dimension of the array, and that's the full width, then
      // just omit it since it's the same
      this.dimensionAccess = dimensionAccess;
      this.sliceUpperIndex = null;
      this.sliceLowerIndex = null;
    } else if (port is LogicArray &&
        sliceLowerIndex == 0 &&
        sliceUpperIndex != null &&
        dimensionAccess != null &&
        dimensionAccess.length == (port as LogicArray).dimensions.length &&
        (port as LogicArray).elementWidth == sliceUpperIndex + 1) {
      // if we have something like [7:0] on an array at the end, and that's the
      // full width, then just omit it since it's the same
      this.dimensionAccess = dimensionAccess;
      this.sliceUpperIndex = null;
      this.sliceLowerIndex = null;
    } else if (port is! LogicArray &&
        sliceLowerIndex == 0 &&
        sliceUpperIndex != null &&
        (dimensionAccess == null || dimensionAccess.isEmpty) &&
        port.width == sliceUpperIndex + 1) {
      // if we have something like [7:0] on a non-array at the end and it's the
      // full width, then just omit it since it's the same
      this.dimensionAccess = null;
      this.sliceUpperIndex = null;
      this.sliceLowerIndex = null;
    } else {
      this.dimensionAccess = dimensionAccess;
      this.sliceUpperIndex = sliceUpperIndex;
      this.sliceLowerIndex = sliceLowerIndex;
    }
  }

  /// Extracts port access components from a port access string.
  ///
  /// Parses complex port access expressions to extract the base port name,
  /// array dimension indices, and slice bounds. This is a utility method used
  /// by factory constructors to decode access strings.
  ///
  /// Returns a record containing:
  /// - `portName`: The base port identifier
  /// - `dimensionAccess`: List of array indices (null if none)
  /// - `sliceUpperIndex`/`sliceLowerIndex`: Slice bounds (null if no slicing)
  static ({
    String portName,
    int? sliceLowerIndex,
    int? sliceUpperIndex,
    List<int>? dimensionAccess
  }) extractPortAccessSliceComponents(String portAccessString) {
    if (StandardPortReference._isStandardAccess(portAccessString)) {
      // if it's a standard port reference, just return the name and empty
      // dimension access
      return (
        portName: portAccessString,
        sliceLowerIndex: null,
        sliceUpperIndex: null,
        dimensionAccess: null
      );
    }

    final match = _sliceAccessRegex.firstMatch(portAccessString);

    if (match == null) {
      throw RohdBridgeException('Invalid port slice access string');
    }

    final portName = match.group(1)!;

    final bracketMatches =
        _bracketedAreas.allMatches(portAccessString).toList();

    final dimensionAccess = <int>[];
    int? sliceUpperIndex;
    int? sliceLowerIndex;

    // loop through all the groups in the match, and for each one:
    //  - if it has a :, split it and set the slice indices
    //  - if not, then put it into dimensionAccess
    // we don't know how many dimensions there may be, so keep looking til end
    for (final bracketMatch in bracketMatches) {
      final group = bracketMatch.group(1)!;

      assert(sliceLowerIndex == null,
          'should only be one slice, and the last one');
      assert(sliceUpperIndex == null,
          'should only be one slice, and the last one');

      if (group.contains(':')) {
        final sliceParts = group.split(':');
        sliceLowerIndex = int.parse(sliceParts[1]);
        sliceUpperIndex = int.parse(sliceParts[0]);
      } else {
        dimensionAccess.add(int.parse(group));
      }
    }

    return (
      portName: portName,
      sliceLowerIndex: sliceLowerIndex,
      sliceUpperIndex: sliceUpperIndex,
      dimensionAccess: dimensionAccess.isEmpty ? null : dimensionAccess
    );
  }

  /// Creates a slice port reference from a port access string.
  ///
  /// Parses the [portAccessString] to create the appropriate slice reference.
  /// The string must contain either array indexing (e.g., `[3]`) or slicing
  /// (e.g., `[7:0]`) or both.
  ///
  /// Throws an exception if the string doesn't contain any slicing or dimension
  /// access, as that would be a simple [StandardPortReference].
  factory SlicePortReference.fromString(
      BridgeModule module, String portAccessString) {
    final components = extractPortAccessSliceComponents(portAccessString);
    final portName = components.portName;
    final sliceLowerIndex = components.sliceLowerIndex;
    final sliceUpperIndex = components.sliceUpperIndex;
    final dimensionAccess = components.dimensionAccess;

    if (sliceUpperIndex == null &&
        sliceLowerIndex == null &&
        dimensionAccess == null) {
      throw RohdBridgeException(
          'SlicePortReference must have either slicing or dimension access.');
    }

    return SlicePortReference(module, portName,
        dimensionAccess: dimensionAccess,
        sliceUpperIndex: sliceUpperIndex,
        sliceLowerIndex: sliceLowerIndex);
  }

  @override
  String toString() => [
        portName,
        dimensionAccess?.map((e) => '[$e]').join(),
        if (hasSlicing) '[$sliceUpperIndex:$sliceLowerIndex]'
      ].nonNulls.join();

  /// Utility for comparing dimension access lists for equality.
  static const ListEquality<int> _listEquality = ListEquality<int>();

  @override
  @internal
  void getsInternal(PortReference other) {
    var receiverPort = _relativeReceiverAndDriver(other).receiver;
    final otherDriver = _relativeDriverSubset(other);

    int? leafIndex;

    if ((receiverPort is! LogicArray && port is! LogicArray) ||
        ((receiverPort is LogicArray) && (port is LogicArray)) &&
            _listEquality.equals(
                receiverPort.dimensions, (port as LogicArray).dimensions)) {
      // shape of the driver (if applicable) matches
      if (dimensionAccess != null) {
        for (final index in dimensionAccess!) {
          if (receiverPort is! LogicArray) {
            leafIndex = index;
            break;
          }
          receiverPort = receiverPort.elements[index];
        }
      }
    } else {
      getsLogic(other.portSubsetLogic);
      return;
    }

    assert(!((leafIndex != null) && hasSlicing),
        'cannot have both slicing and a leaf index');

    if (otherDriver is Logic) {
      if (leafIndex != null) {
        receiverPort.assignSubset([otherDriver], start: leafIndex);
      } else if (hasSlicing) {
        final startSliceIndex = leafIndex ?? sliceLowerIndex ?? 0;
        if (otherDriver.elements.length == _sliceCount) {
          // elements line up, assign them directly
          receiverPort.assignSubset(otherDriver.elements,
              start: sliceLowerIndex!);
        } else {
          // elements don't line up, need to do some fanciness per-element
          var receiverSliceIndex = 0;
          for (final element in receiverPort.elements
              .getRange(startSliceIndex, startSliceIndex + _sliceCount!)) {
            final otherDriverRange = otherDriver.getRange(
                receiverSliceIndex, receiverSliceIndex + element.width);

            if (receiverPort is LogicArray) {
              element <= otherDriverRange;
            } else {
              receiverPort.assignSubset(otherDriverRange.elements,
                  start: startSliceIndex + receiverSliceIndex);
            }

            receiverSliceIndex += element.width;
          }
        }
      } else {
        receiverPort <= otherDriver;
      }
    } else if (otherDriver is List<Logic>) {
      if (leafIndex != null) {
        assert(otherDriver.length == 1,
            'cannot assign multiple elements to a leaf index');
        receiverPort.assignSubset(otherDriver, start: leafIndex);
      } else if (hasSlicing) {
        if (otherDriver.length == _sliceCount) {
          // elements line up, assign them directly
          receiverPort.assignSubset(otherDriver, start: sliceLowerIndex!);
        } else {
          // elements don't line up, need to do some fanciness per-element
          var receiverSliceIndex = 0;
          final swizzledOtherDriver = otherDriver.rswizzle();
          for (final element in receiverPort.elements
              .getRange(sliceLowerIndex!, sliceUpperIndex! + 1)) {
            final otherDriverRange = swizzledOtherDriver.getRange(
                receiverSliceIndex, receiverSliceIndex + element.width);

            if (receiverPort is LogicArray) {
              element <= otherDriverRange;
            } else {
              receiverPort.assignSubset(otherDriverRange.elements,
                  start: sliceLowerIndex! + receiverSliceIndex);
            }

            receiverSliceIndex += element.width;
          }
        }
      } else {
        receiverPort <= otherDriver.rswizzle();
      }
    } else {
      throw RohdBridgeException('Invalid driver type: $otherDriver');
    }
  }

  @override
  dynamic get _externalPortSubset => _getPortSubset(_externalPort);

  @override
  dynamic get _internalPortSubset => _getPortSubset(_internalPort);

  @override
  late final dynamic portSubset = _getPortSubset(port);
  dynamic _getPortSubset(Logic p) {
    var d = p;

    if (dimensionAccess != null) {
      for (final index in dimensionAccess!) {
        d = d.elements[index];
      }
    }

    if (hasSlicing) {
      if (d is LogicArray) {
        return d.elements
            .getRange(sliceLowerIndex!, sliceUpperIndex! + 1)
            .toList(growable: false);
      } else {
        return d.getRange(sliceLowerIndex!, sliceUpperIndex! + 1);
      }
    } else {
      return d;
    }
  }

  /// The bit width of the port subset this reference represents.
  ///
  /// For array elements, this returns the element width. For bit slices, this
  /// returns the slice width. For combinations, it calculates the appropriate
  /// total width.
  int get subsetElementWidth => _elementWidthAndDimensions.elementWidth;

  /// The array dimensions of the port subset, if applicable.
  ///
  /// Returns the dimensional structure of the subset after applying array
  /// indexing and slicing operations. `null` if the result is a simple scalar
  /// logic signal.
  List<int>? get subsetDimensions => _elementWidthAndDimensions.dimensions;

  /// The number of unpacked dimensions in the port subset, if applicable.
  ///
  /// Returns the count of unpacked dimensions after applying array indexing
  /// and slicing operations. `null` if the result is a simple scalar logic
  /// signal.
  int? get subsetNumUnpackedDimensions =>
      _elementWidthAndDimensions.numUnpackedDimensions;

  /// Cached calculation of element width and dimensions for the subset.
  ///
  /// This computes the effective width and dimensionality that results from
  /// applying the dimension access and slicing operations to the original port.
  late final _elementWidthAndDimensions = _getElementWidthAndDimensions();
  ({int elementWidth, List<int>? dimensions, int? numUnpackedDimensions})
      _getElementWidthAndDimensions() {
    var sig = port;
    int? leafIndex;
    if (dimensionAccess != null) {
      for (final index in dimensionAccess!) {
        if (sig is! LogicArray) {
          leafIndex = index;
          break;
        }
        sig = sig.elements[index];
      }
    }

    assert(!((leafIndex != null) && hasSlicing),
        'cannot have both slicing and a leaf index');

    if (leafIndex != null) {
      assert(sig is! LogicArray, 'should not be an array');
      return (elementWidth: 1, dimensions: null, numUnpackedDimensions: null);
    } else if (hasSlicing) {
      final sliceWidth = sliceUpperIndex! - sliceLowerIndex! + 1;
      if (sig is LogicArray) {
        return (
          elementWidth: sig.elementWidth,
          dimensions: List.of(sig.dimensions)..[0] = sliceWidth,
          numUnpackedDimensions: sig.numUnpackedDimensions
        );
      } else {
        // non-array, normal logic
        return (
          elementWidth: sliceWidth,
          dimensions: null,
          numUnpackedDimensions: null
        );
      }
    } else {
      if (sig is LogicArray) {
        // still an array, no slicing
        return (
          elementWidth: sig.elementWidth,
          dimensions: sig.dimensions,
          numUnpackedDimensions: sig.numUnpackedDimensions
        );
      } else {
        // non-array, normal logic
        return (
          elementWidth: sig.width,
          dimensions: null,
          numUnpackedDimensions: null
        );
      }
    }
  }

  @override
  PortReference replicateTo(BridgeModule newModule, PortDirection direction,
      {String? newPortName}) {
    newPortName ??= portName;

    if (subsetDimensions == null) {
      newModule.createPort(newPortName, direction, width: subsetElementWidth);
    } else {
      newModule.createArrayPort(newPortName, direction,
          dimensions: subsetDimensions!,
          elementWidth: subsetElementWidth,
          numUnpackedDimensions: subsetNumUnpackedDimensions!);
    }

    return PortReference.fromString(newModule, newPortName);
  }

  @override
  void drivesLogic(Logic other) {
    other <= portSubsetLogic;
  }

  @override
  void getsLogic(Logic other) {
    var receiver = _externalPort;
    // we must look at the *port* for dimension analysis
    int? leafIndex;
    var startIdx = 0;
    var receiverStartIdx = 0;
    var elementWidth = port.elements.first.width;
    var endIdx = port.width - 1;

    var portElement = port;
    if (dimensionAccess != null) {
      for (final index in dimensionAccess!) {
        if (portElement is! LogicArray) {
          leafIndex = index;
          elementWidth = portElement.elements.first.width;
          break;
        }

        portElement = portElement.elements[index];
        elementWidth = portElement.width;
        startIdx += index * elementWidth;
        endIdx = startIdx + elementWidth - 1;

        if (receiver is LogicArray) {
          receiver = receiver.elements[index];
        } else {
          receiverStartIdx += index * elementWidth;
        }
      }
    }

    elementWidth = portElement.elements.first.width;

    if (hasSlicing) {
      startIdx += sliceLowerIndex! * elementWidth;
      endIdx = startIdx + _sliceCount! * elementWidth - 1;

      if (receiver is LogicArray) {
        receiverStartIdx = sliceLowerIndex!;
      } else {
        receiverStartIdx += sliceLowerIndex! * elementWidth;
      }
    }

    if (leafIndex != null) {
      startIdx += leafIndex;
      endIdx = startIdx + elementWidth - 1;

      if (receiver is! LogicArray) {
        receiverStartIdx += leafIndex;
      }
    }

    final receiverDriver = Logic(width: endIdx - startIdx + 1);
    receiverDriver <= other;

    if (receiver is LogicArray) {
      if (hasSlicing) {
        final receivers = receiver.elements
            .getRange(receiverStartIdx, receiverStartIdx + _sliceCount!);
        var incrIndex = 0;
        for (final r in receivers) {
          r <= receiverDriver.getRange(incrIndex, incrIndex + r.width);
          incrIndex += r.width;
        }
      } else {
        // this is a full sub-array
        receiver <= receiverDriver;
      }
    } else {
      receiver.assignSubset(receiverDriver.elements, start: receiverStartIdx);
    }
  }

  /// Computes new slice indices when creating a sub-slice of this reference.
  ///
  /// When slicing an already-sliced port reference, this method calculates the
  /// effective indices in the original port coordinate system. The [endIndex]
  /// and [startIndex] are relative to this slice's coordinate system.
  ///
  /// Returns a tuple of (newLowerIndex, newUpperIndex) in the original port's
  /// coordinate system.
  @protected
  (int newLowerIndex, int newUpperIndex) getUpdatedSliceIndices(
      int endIndex, int startIndex) {
    final newRangeSize = endIndex - startIndex + 1;
    final newLowerIndex = (sliceLowerIndex ?? 0) + startIndex;
    final newUpperIndex = newLowerIndex + newRangeSize - 1;

    return (newLowerIndex, newUpperIndex);
  }

  @override
  PortReference slice(int endIndex, int startIndex) {
    final (newLowerIndex, newUpperIndex) =
        getUpdatedSliceIndices(endIndex, startIndex);

    return SlicePortReference(
      module,
      portName,
      dimensionAccess: dimensionAccess,
      sliceLowerIndex: newLowerIndex,
      sliceUpperIndex: newUpperIndex,
    );
  }

  /// The parent [PortReference] of this [SlicePortReference], with slicing or
  /// the least significant dimension removed.
  ///
  /// For example, if this reference is `myPort[2][3:1]`, the parent reference
  /// would be `myPort[2]`.  If the reference is `myPort[7:0]`, the parent
  /// reference would be `myPort`. If the reference is `myPort[3][2][1]`, the
  /// parent reference would be `myPort[3][2]`.
  ///
  /// If there are no slices or dimension accesses left, then `null` is
  /// returned.
  PortReference? get parentPortReference {
    final List<int>? newDimensionAccess;

    if (hasSlicing) {
      newDimensionAccess = dimensionAccess;
    } else if (dimensionAccess != null && dimensionAccess!.isNotEmpty) {
      newDimensionAccess =
          dimensionAccess!.sublist(0, dimensionAccess!.length - 1);
    } else {
      return null;
    }

    if (newDimensionAccess != null && newDimensionAccess.isNotEmpty) {
      return SlicePortReference(
        module,
        portName,
        dimensionAccess: newDimensionAccess,
      );
    } else {
      return StandardPortReference(module, portName);
    }
  }
}
