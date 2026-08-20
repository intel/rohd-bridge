// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// benchmark_test.dart
// Smoke tests for benchmarks.
//
// 2026 August 20
// Author: Max Korbel <max.korbel@intel.com>

import 'package:test/test.dart';

import '../benchmark/connection_extractor_benchmark.dart';

void main() {
  group('benchmark', tags: 'benchmark', () {
    late ConnectionExtractorBenchmarkDesign design;

    setUpAll(() async {
      design = ConnectionExtractorBenchmarkDesign(
        modulePairs: 2,
        interfacesPerPair: 2,
        portsPerDirection: 3,
        adHocConnectionsPerPair: 4,
      );
      await design.top.build();
      design.validateStructure();
    });

    test('connection extractor interface-aware', () {
      final benchmark = ConnectionExtractorBenchmark(
        design.modules,
        includeInterfaceConnections: true,
        expectedConnectionCount: design.expectedCompactConnectionCount,
      )..run();

      expect(
        benchmark.latestConnections,
        hasLength(design.expectedCompactConnectionCount),
      );
    });

    test('connection extractor pin-only', () {
      final benchmark = ConnectionExtractorBenchmark(
        design.modules,
        includeInterfaceConnections: false,
        expectedConnectionCount: design.expectedPinConnectionCount,
      )..run();

      expect(
        benchmark.latestConnections,
        hasLength(design.expectedPinConnectionCount),
      );
    });
  });
}
