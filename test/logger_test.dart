// Copyright (C) 2026 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// logger_test.dart
// Unit tests for MI (multiple instances).
//
// 2026 January 2
// Author: Max Korbel <max.korbel@intel.com>

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

void main() {
  test('unconfigured logger works', () async {
    // just make sure no exceptions are thrown

    final top = BridgeModule('top');

    const outPath = 'tmp_test/unconfigured_logger_test';
    await top.buildAndGenerateRTL(outputPath: outPath);

    Directory(outPath).deleteSync(recursive: true);
  });

  test('configured logger works', () async {
    const logPath = 'tmp_test/cfg_logger/cfg_logger.log';
    RohdBridgeLogger.configureLogger(logPath, printLevel: Level.OFF);

    final top = BridgeModule('top');

    const outPath = 'tmp_test/cfg_logger/';
    await top.buildAndGenerateRTL(outputPath: outPath);

    await RohdBridgeLogger.terminate();

    expect(File(logPath).existsSync(), isTrue);
    expect(File(logPath).readAsStringSync().contains('done!'), isTrue);

    Directory(outPath).deleteSync(recursive: true);
  });
}
