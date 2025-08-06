// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// example_test.dart
// Tests that the example(s) work properly.
//
// 2024 July
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'dart:io';

import 'package:test/test.dart';
import '../example/example.dart' as example;

void main() {
  test('example runs properly', () async {
    await example.main();

    // clean up
    Directory('output_example').deleteSync(recursive: true);
  });
}
