// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// benchmark.dart
// Runs all ROHD Bridge benchmarks.
//
// 2026 August 20
// Author: Max Korbel <max.korbel@intel.com>

import 'connection_extractor_benchmark.dart' as connection_extractor;

Future<void> main() async {
  await connection_extractor.main();
}
