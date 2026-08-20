// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// connection_extractor_benchmark.dart
// Benchmarks extracting connections from a large synthetic design.
//
// 2026 August 20
// Author: Max Korbel <max.korbel@intel.com>

// Benchmark declarations are public so that the benchmark smoke test can
// import them, but they are not part of the package's public API.
// ignore_for_file: avoid_print

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

class BenchmarkPairInterface extends PairInterface {
  BenchmarkPairInterface(this.portsPerDirection)
      : super(
          portsFromProvider: [
            for (var i = 0; i < portsPerDirection; i++)
              Logic.port('request_$i', 1 + i % 32),
          ],
          portsFromConsumer: [
            for (var i = 0; i < portsPerDirection; i++)
              Logic.port('response_$i', 1 + (i * 3) % 32),
          ],
        );

  final int portsPerDirection;

  @override
  BenchmarkPairInterface clone() => BenchmarkPairInterface(portsPerDirection);
}

class ConnectionExtractorBenchmarkDesign {
  ConnectionExtractorBenchmarkDesign({
    this.modulePairs = 32,
    this.interfacesPerPair = 5,
    this.portsPerDirection = 8,
    this.adHocConnectionsPerPair = 64,
  }) : top = BridgeModule('connection_extractor_benchmark_top') {
    for (var pair = 0; pair < modulePairs; pair++) {
      final provider = BridgeModule('benchmark_provider')
        ..createPort('clock', PortDirection.input);
      final consumer = BridgeModule('benchmark_consumer');

      for (var interfaceIndex = 0;
          interfaceIndex < interfacesPerPair;
          interfaceIndex++) {
        final interfaceName = 'bus_$interfaceIndex';
        provider.addInterface(
          BenchmarkPairInterface(portsPerDirection),
          name: interfaceName,
          role: PairRole.provider,
        );
        consumer.addInterface(
          BenchmarkPairInterface(portsPerDirection),
          name: interfaceName,
          role: PairRole.consumer,
        );
      }

      for (var connection = 0;
          connection < adHocConnectionsPerPair;
          connection++) {
        final width = 1 + connection % 64;
        provider.createPort(
          'source_$connection',
          PortDirection.output,
          width: width,
        );
        consumer.createPort(
          'destination_$connection',
          PortDirection.input,
          width: width,
        );
      }

      top
        ..addSubModule(provider)
        ..addSubModule(consumer);
      provider.port('clock').punchUpTo(top, newPortName: 'clock_$pair');

      for (var interfaceIndex = 0;
          interfaceIndex < interfacesPerPair;
          interfaceIndex++) {
        final interfaceName = 'bus_$interfaceIndex';
        connectInterfaces(
          provider.interface(interfaceName),
          consumer.interface(interfaceName),
        );
      }

      for (var connection = 0;
          connection < adHocConnectionsPerPair;
          connection++) {
        connectPorts(
          provider.port('source_$connection'),
          consumer.port('destination_$connection'),
        );
      }
    }
  }

  final int modulePairs;
  final int interfacesPerPair;
  final int portsPerDirection;
  final int adHocConnectionsPerPair;
  final BridgeModule top;

  Iterable<BridgeModule> get modules => top.subBridgeModules;

  int get expectedModuleCount => 2 * modulePairs;

  int get expectedPhysicalPortCount =>
      modulePairs *
      (1 +
          4 * interfacesPerPair * portsPerDirection +
          2 * adHocConnectionsPerPair);

  int get expectedCompactConnectionCount =>
      modulePairs * (interfacesPerPair + adHocConnectionsPerPair);

  int get expectedPinConnectionCount =>
      modulePairs *
      (2 * interfacesPerPair * portsPerDirection + adHocConnectionsPerPair);

  int get physicalPortCount => modules.fold(
        0,
        (count, module) =>
            count +
            module.inputs.length +
            module.outputs.length +
            module.inOuts.length,
      );

  void validateStructure() {
    if (modules.length != expectedModuleCount) {
      throw StateError(
        'Expected $expectedModuleCount modules, found ${modules.length}.',
      );
    }
    if (physicalPortCount != expectedPhysicalPortCount) {
      throw StateError(
        'Expected $expectedPhysicalPortCount physical ports, '
        'found $physicalPortCount.',
      );
    }
  }
}

class ConnectionExtractorBenchmark extends BenchmarkBase {
  ConnectionExtractorBenchmark(
    Iterable<BridgeModule> modules, {
    required this.includeInterfaceConnections,
    required this.expectedConnectionCount,
  })  : modules = List.unmodifiable(modules),
        super(
          includeInterfaceConnections
              ? 'ConnectionExtractor.interfaceAware'
              : 'ConnectionExtractor.pinOnly',
        );

  final List<BridgeModule> modules;
  final bool includeInterfaceConnections;
  final int expectedConnectionCount;

  Set<Connection> latestConnections = const {};

  @override
  void run() {
    latestConnections = ConnectionExtractor(
      modules,
      includeInterfaceConnections: includeInterfaceConnections,
    ).connections;

    if (latestConnections.length != expectedConnectionCount) {
      throw StateError(
        'Expected $expectedConnectionCount connections, '
        'found ${latestConnections.length}.',
      );
    }
  }
}

Future<void> main() async {
  final design = ConnectionExtractorBenchmarkDesign();
  final buildWatch = Stopwatch()..start();
  await design.top.build();
  buildWatch.stop();
  design.validateStructure();

  print(
    'build=${buildWatch.elapsedMilliseconds}ms '
    'modules=${design.modules.length} ports=${design.physicalPortCount}',
  );

  ConnectionExtractorBenchmark(
    design.modules,
    includeInterfaceConnections: true,
    expectedConnectionCount: design.expectedCompactConnectionCount,
  ).report();
  ConnectionExtractorBenchmark(
    design.modules,
    includeInterfaceConnections: false,
    expectedConnectionCount: design.expectedPinConnectionCount,
  ).report();
}
