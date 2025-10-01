// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// rohd_bridge_logger.dart
// Logger for ROHD Bridge.
//
// 2024
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'package:rohd_bridge/rohd_bridge.dart';

/// Extension on [Logger] to throw an exception if an [error] is encountered.
extension LoggerError on Logger {
  /// Creates a [severe] message and throws an exception if
  /// [RohdBridgeLogger.continueOnError] is `false`.
  void error(String message) {
    severe(message);
    if (!RohdBridgeLogger.continueOnError) {
      throw RohdBridgeException('ROHD Bridge failed... $message');
    }
  }

  /// Log a section separator.
  void sectionSeparator(String section) {
    RohdBridgeLogger._sectionSeparator(section);
  }
}

/// Loggger for ROHD Bridge tool
abstract class RohdBridgeLogger {
  /// If set to `true`, then errors will be printed without causing an immediate
  /// exception halting execution.
  static bool continueOnError = false;

  /// If set to`true`, some additional log will be printed
  /// which will be helpful for debug
  static bool enableDebugMesage = false;

  /// The file sink to write to.
  static IOSink? fileSink;

  static late Level _printLevel;

  /// logger for rohd_bridge
  static final Logger logger = Logger('ROHD Bridge');

  /// Sets up logging to dump to [filePath] and print to console based on
  /// [printLevel] and [rootLevel].
  ///
  /// The [rootLevel] will set the level of the [Logger.root] to the given
  /// level.
  ///
  /// The [printLevel] is the [Level] from [Logger]s that should be printed to
  /// the console. This can at most print [Level]s that are enabled in the
  /// [Logger.root].
  ///
  /// If [continueOnError] is set to `false`, then an exception will be thrown
  /// immediately upon encountering an error.
  static void configureLogger(
    String filePath, {
    Level printLevel = Level.ALL,
    Level rootLevel = Level.ALL,
    bool continueOnError = false,
    bool enableDebugMesage = false,
  }) {
    // Clean up existing logger subscriptions and file sink
    Logger.root.clearListeners();
    if (fileSink != null) {
      unawaited(fileSink!.close());
    }
    fileSink = null;

    RohdBridgeLogger.continueOnError = continueOnError;
    Logger.root.level = rootLevel;
    _printLevel = printLevel;

    fileSink = File(filePath).openWrite();

    Logger.root.onRecord.listen((record) {
      final message =
          '${record.time}: ${record.level.name}: '
          '${record.message}\n';

      _handleMessage(message, record.level);
    });
  }

  static void _handleMessage(String message, [Level? level]) {
    fileSink!.write(message);
    if (level != null && level >= _printLevel) {
      // ignore: avoid_print
      print(message);
    }
  }

  /// Terminate the logger and close the file sink.
  static Future<void> terminate() async {
    Logger.root.clearListeners();
    await flush();
    await fileSink!.close();
    fileSink = null;
  }

  /// Flush the file sink.
  static Future<void> flush() async {
    await fileSink!.flush();
  }

  /// Log a section separator
  static void _sectionSeparator(String section) {
    const netLength = 150;
    final paddingLength = (netLength - section.length) ~/ 2 - 1;
    final fullLine = '*' * netLength;
    final leftPadding = '*' * paddingLength;
    final rightPadding = '*' * (netLength - paddingLength - section.length - 2);

    _handleMessage('''

    $fullLine
    $leftPadding ${section.toUpperCase()} $rightPadding
    $fullLine
  ''');
  }
}
