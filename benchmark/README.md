# Benchmarking ROHD Bridge

This directory contains synthetic benchmarks for comparing the relative
performance of ROHD Bridge features before and after a change.

Run all benchmarks with:

```shell
dart run benchmark/benchmark.dart
```

Run only the connection extractor benchmark with:

```shell
dart run benchmark/connection_extractor_benchmark.dart
```

The default connection extractor design uses only public ROHD and ROHD Bridge
APIs. It contains 64 child modules, 160 complete interface connections, and
2,048 ad-hoc port connections. The benchmark validates these structural
results before reporting timings:

| Result | Expected |
| --- | ---: |
| Child modules | 64 |
| Physical child ports | 9,248 |
| Interface-aware connections | 2,208 |
| Pin-only connections | 4,608 |

Compare results on the same host and Dart version. Do not use absolute timing
assertions in tests; timings vary by runtime and machine.

---

Copyright (C) 2026 Intel Corporation  
SPDX-License-Identifier: BSD-3-Clause
