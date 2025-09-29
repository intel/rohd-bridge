
// rohd_bridge_logger_test.dart
// Tests for ROHD Bridge Logger functionality.


import 'dart:io';
import 'package:test/test.dart';
import 'package:logging/logging.dart';
import 'package:rohd_bridge/src/rohd_bridge_logger.dart';

void main() {
  group('RohdBridgeLogger', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rohd_bridge_test');
    });

    tearDown(() async {
      await RohdBridgeLogger.terminate();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('configureLogger cleans up previous subscriptions', () async {
      final logFile1 = '${tempDir.path}/test1.log';
      final logFile2 = '${tempDir.path}/test2.log';

      // Configure logger first time
      RohdBridgeLogger.configureLogger(logFile1);

      // Log a message
      RohdBridgeLogger.logger.info('First configuration');
      await RohdBridgeLogger.flush();

      // Reconfigure logger - this should clean up previous subscriptions
      RohdBridgeLogger.configureLogger(logFile2);

      // Log another message after reconfiguration
      RohdBridgeLogger.logger.info('Second configuration');
      await RohdBridgeLogger.flush();

      // Verify first log file exists and has content from first configuration
      expect(File(logFile1).existsSync(), isTrue);
      final firstLogContent = await File(logFile1).readAsString();
      expect(firstLogContent, contains('First configuration'));

      // Verify second log file exists and has content from second configuration
      expect(File(logFile2).existsSync(), isTrue);
      final secondLogContent = await File(logFile2).readAsString();
      expect(secondLogContent, contains('Second configuration'));

      // Second log should not contain first message (proves no duplicate logging)
      expect(secondLogContent, isNot(contains('First configuration')));

      // First log should not contain second message (proves cleanup worked)
      expect(firstLogContent, isNot(contains('Second configuration')));
    });

    test('configureLogger handles null fileSink gracefully', () {
      // This should not throw even when fileSink is initially null
      expect(() => RohdBridgeLogger.configureLogger('${tempDir.path}/test.log'),
             returnsNormally);
    });

    test('multiple reconfigurations work correctly', () async {
      final logFiles = <String>[];

      // Configure logger multiple times
      for (int i = 0; i < 3; i++) {
        final logFile = '${tempDir.path}/test$i.log';
        logFiles.add(logFile);

        RohdBridgeLogger.configureLogger(logFile);
        RohdBridgeLogger.logger.info('Message $i');
        await RohdBridgeLogger.flush();
      }

      // Each log file should exist and contain only its respective message
      for (int i = 0; i < 3; i++) {
        expect(File(logFiles[i]).existsSync(), isTrue);
        final content = await File(logFiles[i]).readAsString();
        expect(content, contains('Message $i'));

        // Should not contain messages from other configurations
        for (int j = 0; j < 3; j++) {
          if (i != j) {
            expect(content, isNot(contains('Message $j')));
          }
        }
      }
    });
  });
}
