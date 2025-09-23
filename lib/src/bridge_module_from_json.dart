// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// bridge_module_from_json.dart
// Additional support for populating BridgeModule from JSON.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

// TODO(mkorbel1): document JSON schemas

/// Extension methods for [BridgeModule] to support JSON parsing.
extension BridgeModuleFromJson on BridgeModule {
  /// Populates ports, interfaces, and parameters from JSON representing the
  /// full module.
  void addFromJson(Map<String, dynamic> jsonContents) {
    if (jsonContents['name'] != definitionName) {
      throw RohdBridgeException(
          'Module name ${jsonContents['name']} in RTL file does not match the '
          'module name $definitionName');
    }

    final paramMap =
        jsonContents['moduleParameters'] as Map<String, dynamic>? ?? {};
    final parameters = addParametersFromJson(paramMap);

    if (jsonContents.containsKey('portList')) {
      addPortsFromJson(jsonContents['portList'] as List<dynamic>, parameters);
    }

    if (jsonContents['complexPortMemberToRange'] is Map<String, dynamic>) {
      addStructMapsFromJson(
          jsonContents['complexPortMemberToRange'] as Map<String, dynamic>);
    }

    if (jsonContents['busInterfaces'] != null) {
      addInterfacesFromJson(jsonContents['name'] as String,
          jsonContents['busInterfaces'] as Map<String, dynamic>, parameters);
    }
  }

  /// Calls [addStructMap] for each entry in the [structInfo] map.
  void addStructMapsFromJson(Map<String, dynamic> structInfo) {
    final structInfoAdjusted = _getStructMap(structInfo);
    for (final entry in structInfoAdjusted.entries) {
      addStructMap(entry.key, port(entry.value));
    }
  }

  /// Create ports in the module based on the [portInfo] and [parameters].
  void addPortsFromJson(
      List<dynamic> portInfo, Map<String, String> parameters) {
    final portInfoAdjusted = _getPortInfo(portInfo);
    // Create all necessary ports in the module
    for (final portDetails in portInfoAdjusted) {
      final portName = portDetails['name']!;
      final direction = PortDirection.fromString(portDetails['direction']!);
      final packedRanges = portDetails['packedRanges']?.toString() ?? '';
      final unpackedRanges = portDetails['unpackedRanges']?.toString() ?? '';
      final fullRange = unpackedRanges + packedRanges;
      //This dimensions will be the same as `LogicArray.dimensions`
      final dimensions = _getDimension(fullRange, parameters);
      var numUnpackedDimensions = 0;
      if (unpackedRanges != '') {
        numUnpackedDimensions =
            _getDimension(unpackedRanges, parameters).length;
      }
      //Single dimensional port
      if (dimensions.length == 1 && numUnpackedDimensions == 0) {
        createPort(portName, direction, width: dimensions.first);
      } else {
        // Multi-dimensional port
        final upperDimensions = List.of(dimensions);
        final elementWidth = numUnpackedDimensions < dimensions.length
            ? upperDimensions.removeLast()
            : 1;
        createArrayPort(portName, direction,
            dimensions: upperDimensions,
            elementWidth: elementWidth,
            numUnpackedDimensions: numUnpackedDimensions);
      }
    }
  }

  /// Returns a json to pass to [BridgeInterface.ofJson]. This json is used to
  /// create a [BridgeInterface] object.
  Map<String, dynamic> _getBridgeIntfJson(
      {required Map<String, dynamic> intfMap}) {
    final vendor = intfMap['vendor'] as String;
    final library = intfMap['library'] as String;
    final name = intfMap['name'] as String;
    final version = intfMap['version'] as String;
    final mode = _getPairRole(intfMap['mode'] as String);
    final portsOnProvider = <String, int>{};
    final portsOnConsumer = <String, int>{};
    final portsSharedInouts = <String, int>{};

    final portMaps = intfMap['portMaps'] != null
        ? intfMap['portMaps'] as List<dynamic>
        : <dynamic>[];
    for (final portMap in portMaps) {
      final portMapJson = portMap as Map<String, dynamic>;
      final logicalPortName = portMapJson['logicalPortName']! as String;
      final physicalPortName = portMapJson['physicalPortName']! as String;
      var logicalPortWidth = portMapJson['logicalPortWidth']! as String;
      logicalPortWidth = logicalPortWidth == '<not constrained>'
          ? portMapJson['physicalPortWidth']! as String
          : logicalPortWidth;
      final dir = _getPairDirection(physicalPortName, mode);

      switch (dir) {
        case PairDirection.fromConsumer:
          portsOnConsumer[logicalPortName] = int.parse(logicalPortWidth);

        case PairDirection.fromProvider:
          portsOnProvider[logicalPortName] = int.parse(logicalPortWidth);

        case PairDirection.sharedInputs:
        case PairDirection.commonInOuts:
          portsSharedInouts[logicalPortName] = int.parse(logicalPortWidth);
      }
    }

    return {
      'vendor': vendor,
      'library': library,
      'name': name,
      'version': version,
      'portsOnConsumer': portsOnConsumer,
      'portsOnProvider': portsOnProvider,
      'portsSharedInouts': portsSharedInouts
    };
  }

  /// Returns the [PairDirection] based on the port name and the role.
  PairDirection _getPairDirection(String portName, PairRole mode) {
    final p = port(portName);
    if (p.port.isInput) {
      return mode == PairRole.provider
          ? PairDirection.fromConsumer
          : PairDirection.fromProvider;
    } else if (p.port.isOutput) {
      return mode == PairRole.provider
          ? PairDirection.fromProvider
          : PairDirection.fromConsumer;
    } else if (p.port.isInOut) {
      return PairDirection.sharedInputs;
    } else {
      throw RohdBridgeException(
          'Invalid portmap. $portName is a port in $name');
    }
  }

  /// Check if 'complexPortMemberToRange' exists and is a Map before proceeding.
  static Map<String, String> _getStructMap(Map<String, dynamic> jsonMap) {
    final structMap = <String, String>{};
    jsonMap.forEach((key, value) {
      if (value is Map) {
        value.cast<String, String>().forEach((structMember, unpackedSlice) {
          structMap[structMember] = unpackedSlice;
          // TODO(mkorbel1): we need to instead retain the final slicing
          structMap['$structMember[0]'] = unpackedSlice;
        });
      }
    });
    return structMap;
  }

  /// Creates interfaces based on a JSON input.
  ///
  /// The [parameters] argument is not currently used, but may be useful in the
  /// future.
  void addInterfacesFromJson(String instanceName,
      Map<String, dynamic> busInterfaces, Map<String, String> parameters) {
    for (final MapEntry(key: intfInstName, value: intfInfo)
        in busInterfaces.entries) {
      intfInfo as Map<String, dynamic>;

      final role = _getPairRole(intfInfo['mode'] as String);

      final portMapList = intfInfo['portMaps'] != null
          ? intfInfo['portMaps'] as List<Map<String, dynamic>>
          : <Map<String, dynamic>>[];
      final allUsedPorts = _getUsedPorts(portMapList);
      final thisIntf =
          BridgeInterface.ofJson(_getBridgeIntfJson(intfMap: intfInfo));

      _checkReqPortUsage(thisIntf, allUsedPorts);

      final thisIntfRef = addInterface(
        thisIntf,
        name: intfInstName,
        role: role,
        connect: false,
      );

      for (final portMap in portMapList) {
        final rtlPortName = portMap['physicalPortName'].toString();
        final intfPortName = portMap['logicalPortName'].toString();
        final phyPs = portMap['physicalPartSelect'].toString();
        final logicalPs = portMap['logicalPartSelect'].toString();

        final logPortRef = logicalPs == ''
            ? intfPortName
            : '$intfPortName$logicalPs'.replaceAll(' ', '');
        final phyPortRef = phyPs == ''
            ? rtlPortName
            : '$rtlPortName$phyPs'.replaceAll(' ', '');

        if (thisIntfRef.interface.tryPort(intfPortName) == null) {
          RohdBridgeLogger.logger.error('Port $intfPortName not in interface'
              ' ${thisIntfRef.interface}');
        } else {
          addPortMap(port(phyPortRef), thisIntfRef.port(logPortRef));
        }
      }
    }
  }

  /// Returns pairrole from string
  static PairRole _getPairRole(String role) {
    final ret = role == 'master'
        ? PairRole.provider
        : role == 'slave'
            ? PairRole.consumer
            : role == 'mirroredmaster'
                ? PairRole.consumer
                : PairRole.provider;
    return ret;
  }

  /// Adds parameters to the module from the JSON [parameterList].
  Map<String, String> addParametersFromJson(
      Map<String, dynamic> parameterList) {
    final parameterInfo = <String, String>{};
    parameterList.forEach((key, info) {
      final value = (info as Map<String, dynamic>)['value'] as String;
      final type = info['type'] as String;
      final resolve = info['resolve'] as String;
      // TODO(shankar4): Add support for unpacked ranges as well
      final ranges = (info['packedRanges'] ?? '') as String;

      // resolve = user means module parameter
      // resolve = immediate means localParam
      if (resolve == 'user') {
        final paramType = _getParameterType(type, ranges);
        if (key != value) {
          createParameter(key, value, type: paramType);
          try {
            if (type.toLowerCase() != 'string') {
              final resolvedVal = getInt(value, asIsIfUnparsed: true);
              parameterInfo[key] = resolvedVal.toString();
            }
          } on Exception catch (e) {
            RohdBridgeLogger.logger.error(
                'Parameter $key has value $value which is not resolved \n $e');
          }
        } else {
          RohdBridgeLogger.logger
              .warning('Parameter $key has an illegal value $value');
        }
      } else {
        parameterInfo[key] = value;
      }
    });
    return parameterInfo;
  }

  /// Gets the type of a parameter based on the type and value provided from the
  /// JSON parsing.
  static String _getParameterType(String type, String ranges) {
    if (type == 'bit') {
      if (ranges == '') {
        return type;
      } else {
        return 'bit$ranges';
      }
    }
    return type;
  }

  /// Get the port information from the portList.
  List<Map<String, String>> _getPortInfo(List<dynamic> portList) {
    final portInfo = <Map<String, String>>[];
    for (final port in portList) {
      final newPort = Map<String, String>.from(port as Map<String, dynamic>);

      if (newPort['direction'] == 'in') {
        newPort['direction'] = 'input';
      } else if (newPort['direction'] == 'out') {
        newPort['direction'] = 'output';
      } else if (newPort['direction'] == 'inout') {
        newPort['direction'] = 'inOut';
      }

      portInfo.add(newPort);
    }
    return portInfo;
  }

  /// Takes a list of [portMaps] in an interface present in the json file and
  /// returns a set of all the interface ports mapped to the rtl.
  ///
  /// This is a helper function for JSON parsing.
  Set<String> _getUsedPorts(List<Map<String, dynamic>> portMaps) {
    final usedPorts = <String>{};
    for (final portMap in portMaps) {
      final intfPortName = portMap['logicalPortName'].toString();
      usedPorts.add(intfPortName);
    }

    return usedPorts;
  }

  /// Checks for whether all ports in the interface are being used in the
  /// interface mapping.
  ///
  /// This is a helper function for JSON parsing.
  void _checkReqPortUsage(PairInterface intf, Set<String> usedPorts) {
    final allPorts = intf.getPorts().keys.toList();
    final unusedReqPorts =
        allPorts.where((element) => !usedPorts.contains(element)).toList();
    if (unusedReqPorts.isNotEmpty) {
      RohdBridgeLogger.logger
          .error('Required ports of interface must be mapped. $unusedReqPorts');
    } else {
      return;
    }
  }

  /// Get port dimensions from the range string in Json This will convert string
  /// into list of int to match `LogicArray.dimensions`
  ///
  /// ```dart
  /// parameters['paramA'] = 5;
  /// range = "[paramA-1:0][paramA-2:0]";
  /// getDimension(range, parameters); // [5,4]
  /// ```
  static List<int> _getDimension(String range, Map<String, String> parameters) {
    if (range == '') {
      return [1];
    }

    final dimensions = <int>[];
    var ranges = range.split('][');
    ranges = ranges
        .map((element) => element.replaceAll(RegExp(r'[\[\]]'), ''))
        .toList();

    for (final dimension in ranges) {
      var dimensionWidth = 0;
      final bits = dimension.split(':');
      if (bits.length > 2) {
        throw RohdBridgeException('Range $range can not be calculated. '
            'Expressions is not resolved.');
      } else {
        final lsb = int.parse(bits[1]);
        final msb = int.parse(bits[0]);
        dimensionWidth = msb - lsb + 1;
      }
      dimensions.add(dimensionWidth);
    }
    return dimensions;
  }

  /// Returns a integer value for systemVerilog value.
  ///
  /// eg: 12'd4354 = 4354
  @internal
  @visibleForTesting
  static dynamic getInt(String input, {bool asIsIfUnparsed = false}) {
    try {
      return LogicValue.ofRadixString(input).toBigInt();
    } on LogicValueConstructionException catch (_) {
      if (asIsIfUnparsed) {
        return input;
      } else {
        rethrow;
      }
    }
  }
}
