// Copyright (C) 2024-2025 Intel Corporation
// SPDX-License-Identifier: BSD-3-Clause
//
// port_access_test.dart
// Unit tests for accessing ports and their subsets.
//
// 2024 August
// Authors:
//   Shankar Sharma <shankar.sharma@intel.com>
//   Suhas Virmani <suhas.virmani@intel.com>
//   Max Korbel <max.korbel@intel.com>

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rohd/rohd.dart';
import 'package:rohd_bridge/rohd_bridge.dart';
import 'package:test/test.dart';

@immutable
class PortExample {
  final String portRefSlice;
  final Logic like;
  final int startIndex;

  final int valWidth;
  static const portName = 'myPort';

  final String name;

  final bool alwaysFlatLogicSource;

  @override
  String toString() => name;

  const PortExample(this.name, this.like, this.portRefSlice, this.startIndex,
      {this.alwaysFlatLogicSource = false, this.valWidth = 4});

  Logic toLogic() {
    final portSubset = addPort(PortDirection.output).portSubset;

    if (portSubset is List<Logic>) {
      if (portSubset.first is LogicArray) {
        final exArr = portSubset.first as LogicArray;
        return LogicArray(
            [portSubset.length, ...exArr.dimensions], exArr.elementWidth);
      } else {
        return LogicArray([portSubset.length], portSubset.first.width);
      }
    } else if (portSubset is LogicArray) {
      final dims = portSubset.dimensions;
      final elWidth = portSubset.elementWidth;
      return LogicArray(dims, elWidth);
    } else if (portSubset is Logic) {
      return Logic(width: portSubset.width);
    }

    throw Exception('Unknown port subset type');
  }

  PortReference addPort(PortDirection direction, {String modName = 'mod'}) {
    final mod = BridgeModule(modName);
    if (like is LogicArray) {
      final dims = (like as LogicArray).dimensions;
      final elWidth = (like as LogicArray).elementWidth;
      if (direction == PortDirection.input) {
        mod.addInputArray(
            portName, alwaysFlatLogicSource ? Logic(width: like.width) : null,
            dimensions: dims, elementWidth: elWidth);
      } else if (direction == PortDirection.output) {
        mod.addOutputArray(portName, dimensions: dims, elementWidth: elWidth);
      } else {
        mod.addInOutArray(portName,
            alwaysFlatLogicSource ? LogicArray.net(dims, elWidth) : null,
            dimensions: dims, elementWidth: elWidth);
      }
    } else {
      if (direction == PortDirection.input) {
        mod.addInput(portName, null, width: like.width);
      } else if (direction == PortDirection.output) {
        mod.addOutput(portName, width: like.width);
      } else {
        mod.addInOut(portName, null, width: like.width);
      }
    }

    return mod.port('$portName$portRefSlice');
  }

  LogicValue get putVal => val('x');
  LogicValue get checkVal => val('z');

  LogicValue val(String undriven) => [
        LogicValue.ofString(undriven * (like.width - valWidth - startIndex)),
        LogicValue.ofString('1' * valWidth),
        LogicValue.ofString(undriven * startIndex),
      ].swizzle();
}

void main() {
  final listEq = const ListEquality<int>().equals;

  group('port access parsing', () {
    test('simple port', () {
      final p = (BridgeModule('mod')..addInput('myPort', null)).port('myPort');
      expect(p.portName, 'myPort');
    });

    group('port with slice access', () {
      test('single dimension', () {
        final p =
            (BridgeModule('mod')..addInput('myPort', null)).port('myPort[0]');
        expect(p, isA<SlicePortReference>());
        expect((p as SlicePortReference).portName, 'myPort');
      });

      test('dimensions with no slicing', () {
        final p = (BridgeModule('mod')
              ..addInputArray('myPort', null, dimensions: [3, 4]))
            .port('myPort[1][2]');
        expect(p, isA<SlicePortReference>());
        p as SlicePortReference;
        expect(p.portName, 'myPort');
        expect(listEq(p.dimensionAccess, [1, 2]), isTrue);
        expect(p.sliceLowerIndex, isNull);
        expect(p.sliceUpperIndex, isNull);
      });

      test('dimensions with slicing', () {
        final p = (BridgeModule('mod')
              ..addInputArray('myPort', null, dimensions: [3, 4]))
            .port('myPort[1][2:1]');
        expect(p, isA<SlicePortReference>());
        p as SlicePortReference;
        expect(p.portName, 'myPort');
        expect(listEq(p.dimensionAccess, [1]), isTrue);
        expect(p.sliceLowerIndex, 1);
        expect(p.sliceUpperIndex, 2);
      });

      test('slicing with no dimensions', () {
        final p = (BridgeModule('mod')
              ..addInputArray('myPort', null, dimensions: [8, 4]))
            .port('myPort[5:3]');
        expect(p, isA<SlicePortReference>());
        p as SlicePortReference;
        expect(p.portName, 'myPort');
        expect(p.dimensionAccess, isNull);
        expect(p.sliceLowerIndex, 3);
        expect(p.sliceUpperIndex, 5);
      });

      test('slice examples that pass', () {
        final legalSlices = [
          'myPort[0]',
          'myPort[1:0]',
          'myPort[3][1]',
          'myPort[3][2:1]',
          'myPort[5][4][3:2]',
        ];

        for (final portAccessString in legalSlices) {
          final p = (BridgeModule('mod')
                ..addInputArray('myPort', null,
                    dimensions: [8, 4], elementWidth: 10))
              .port(portAccessString);
          expect(p, isA<SlicePortReference>());
          expect((p as SlicePortReference).portName, 'myPort');
        }
      });

      test('slice examples that fail', () {
        final illegalSlices = [
          'myPort[0:1:2]',
          'myPort[1:0][2]',
          'myPort[0][1:3][4]',
        ];

        for (final portAccessString in illegalSlices) {
          expect(
              () => (BridgeModule('mod')
                    ..addInputArray('myPort', null,
                        dimensions: [8, 4], elementWidth: 10))
                  .port(portAccessString),
              throwsException);
        }
      });

      group('simplification', () {
        test('same upper and lower', () {
          final mod = (BridgeModule('mod')
            ..addInputArray('myPort', null, dimensions: [8, 4]));

          expect(mod.port('myPort[5:5]'), mod.port('myPort[5]'));
        });

        test('array full width slice', () {
          final mod = (BridgeModule('mod')
            ..addInputArray('myPort', null, dimensions: [8, 4]));

          expect(mod.port('myPort[3][3:0]'), mod.port('myPort[3]'));
        });

        test('array full width slice no dims', () {
          final mod = (BridgeModule('mod')
            ..addInputArray('myPort', null, dimensions: [8, 4]));

          expect(mod.port('myPort[7:0]'), mod.port('myPort'));
        });

        test('array element full width slice', () {
          final mod = (BridgeModule('mod')
            ..addInputArray('myPort', null,
                dimensions: [8, 4], elementWidth: 10));

          expect(mod.port('myPort[3][2][9:0]'), mod.port('myPort[3][2]'));
        });

        test('non-array slice full width', () {
          final mod = (BridgeModule('mod')..addInput('myPort', null, width: 8));

          expect(mod.port('myPort[7:0]'), mod.port('myPort'));
        });
      });

      group('slice function', () {
        test('normal to slice', () {
          final mod = (BridgeModule('mod')..addInput('myPort', null, width: 8));
          expect(mod.port('myPort').slice(3, 2), mod.port('myPort[3:2]'));
        });

        test('full width slice', () {
          final mod = (BridgeModule('mod')..addInput('myPort', null, width: 8));
          expect(mod.port('myPort').slice(7, 0), mod.port('myPort'));
        });

        test('slice to smaller slice', () {
          final mod = (BridgeModule('mod')..addInput('myPort', null, width: 8));
          expect(
            mod.port('myPort[6:2]').slice(2, 1),
            mod.port('myPort[4:3]'),
          );
        });

        test('array full to add slice', () {
          final mod = (BridgeModule('mod')
            ..addInputArray('myPort', null,
                dimensions: [8, 4], elementWidth: 5));
          expect(
            mod.port('myPort[3][2]').slice(4, 1),
            mod.port('myPort[3][2][4:1]'),
          );
        });

        test('normal indexed', () {
          final mod = (BridgeModule('mod')..addInput('myPort', null, width: 8));
          expect(mod.port('myPort')[3], mod.port('myPort[3]'));
        });

        test('sliced indexed', () {
          final mod = (BridgeModule('mod')..addInput('myPort', null, width: 8));
          expect(mod.port('myPort[6:2]')[2], mod.port('myPort[4]'));
        });
      });
    });
  });

  group('port reference getsLogic', () {
    test('simple', () {
      final mod = BridgeModule('mod')..addInput('apple', null);

      mod.port('apple').getsLogic(Const(0));
      expect(mod.input('apple').value, LogicValue.of('0'));
    });

    test('subset', () {
      final mod = BridgeModule('mod')..addInput('apple', null, width: 4);

      mod.port('apple[2:1]').getsLogic(Const(2, width: 2));
      expect(mod.input('apple').value, LogicValue.of('z10z'));
    });

    test('gets array', () {
      final mod = BridgeModule('mod')..addInput('apple', null, width: 4);

      mod
          .port('apple[2:1]')
          .getsLogic(LogicArray([2], 1)..gets(Const(2, width: 2)));
      expect(mod.input('apple').value, LogicValue.of('z10z'));
    });

    test('array subset of leaf gets', () {
      final mod = BridgeModule('mod')
        ..addInputArray('apple', null, dimensions: [4], elementWidth: 4);

      mod.port('apple[1][2:1]').getsLogic(Const(2, width: 2));
      expect(mod.input('apple').value,
          LogicValue.of('${'z' * 4}${'z' * 4}z10z${'z' * 4}'));
    });

    test('array subset gets', () {
      final mod = BridgeModule('mod')
        ..addInputArray('apple', null, dimensions: [4], elementWidth: 4);

      mod.port('apple[2:1]').getsLogic(Const(0, width: 8));
      expect(mod.input('apple').value,
          LogicValue.of('${'z' * 4}${'0' * 4}${'0' * 4}${'z' * 4}'));
    });
  });

  group('unprovided driver on input creation and registration', () {
    test('addInput', () {
      final dut = BridgeModule('dut')..addInput('a', null);
      expect(dut.input('a').srcConnection, dut.inputSource('a'));
    });

    test('addInputArray', () {
      final dut = BridgeModule('dut')
        ..addInputArray('a', null, dimensions: [3]);
      expect(dut.input('a').srcConnections.first.parentStructure,
          dut.inputSource('a'));
    });
  });

  group('non-array ports', () {
    test('port of input is input driver', () {
      final dut = BridgeModule('dut')..addInput('a', null);
      expect(dut.port('a').port, dut.input('a'));
    });

    test('port of an output is output', () {
      final dut = BridgeModule('dut')..addOutput('a');
      expect(dut.port('a').port, dut.output('a'));
    });
  });

  group('array ports', () {
    test('port of inputArray is input driver', () {
      final dut = BridgeModule('dut')..addInputArray('a', null);
      expect(dut.port('a').port, dut.input('a'));
    });

    test('port of an output is output', () {
      final dut = BridgeModule('dut')..addOutput('a');
      expect(dut.port('a').port, dut.output('a'));
    });
  });

  test('non-array source for array input', () {
    final dut = BridgeModule('dut')
      ..addOutput('b', width: 8)
      ..addInputArray('a', Logic(width: 8),
          dimensions: [2, 2], elementWidth: 2);

    dut.port('a[1][1:0]').gets(dut.port('b[3:0]'));

    dut.output('b').put(1, fill: true);
    expect(dut.input('a').value, LogicValue.of('1111zzzz'));
  });

  void testInoutResult(PortReference pInEx, PortReference pOutEx,
      PortExample inEx, PortExample outEx) {
    pInEx.port.put(inEx.putVal);
    expect(pOutEx.port.value, outEx.checkVal);

    pInEx.port.put(LogicValue.filled(pInEx.port.width, LogicValue.z));

    pOutEx.port.put(outEx.putVal);
    expect(pInEx.port.value, inEx.checkVal);
  }

  group('connections', () {
    final connType =
        <String, Future<void> Function(PortExample outEx, PortExample inEx)>{
      'port to port': (outEx, inEx) async {
        final pOut = outEx.addPort(PortDirection.output);
        final pIn = inEx.addPort(PortDirection.input)..gets(pOut);

        final pInOut = outEx.addPort(PortDirection.inOut);
        final pInOut2 = inEx.addPort(PortDirection.inOut)..gets(pInOut);

        pOut.port.put(outEx.putVal);
        expect(pIn.port.value, inEx.checkVal);

        testInoutResult(pInOut2, pInOut, inEx, outEx);
      },
      'port to port through hierarchy': (outEx, inEx) async {
        final pOut = outEx.addPort(PortDirection.output);
        final pIn = inEx.addPort(PortDirection.input);
        final pInOut = outEx.addPort(PortDirection.inOut, modName: 'modX');
        final pInOut2 = inEx.addPort(PortDirection.inOut, modName: 'modX1');

        final parSrc = BridgeModule('parSrc')..addSubModule(pOut.module);
        final parDst = BridgeModule('parDst')..addSubModule(pIn.module);
        final parSrcInout = BridgeModule('parSrcInout')
          ..addSubModule(pInOut.module);
        final parDstInout = BridgeModule('parDstInout')
          ..addSubModule(pInOut2.module);

        final top = BridgeModule('top')
          ..addSubModule(parSrc)
          ..addSubModule(parDst)
          ..addSubModule(parSrcInout)
          ..addSubModule(parDstInout);
        connectPorts(pOut, pIn);
        connectPorts(pInOut, pInOut2);

        // to keep hierarchy correct
        top
          ..pullUpPort(pOut.module.createPort('dummy', PortDirection.input))
          ..pullUpPort(pIn.module.createPort('dummy', PortDirection.input))
          ..pullUpPort(pInOut.module.createPort('dummy', PortDirection.input))
          ..pullUpPort(pInOut2.module.createPort('dummy', PortDirection.input));

        await top.build();
        pOut.port.put(outEx.putVal);
        expect(pIn.port.value, inEx.checkVal);

        testInoutResult(pInOut2, pInOut, inEx, outEx);
      },
      'port drives logic': (outEx, inEx) async {
        final lIn = inEx.toLogic();
        final pOut = outEx.addPort(PortDirection.output)..drivesLogic(lIn);

        pOut.port.put(outEx.putVal);
        expect(lIn.value, LogicValue.filled(lIn.width, LogicValue.one));
      },
      'inout port drives logic': (outEx, inEx) async {
        final lIn = inEx.toLogic();
        final pOut = outEx.addPort(PortDirection.inOut)..drivesLogic(lIn);

        pOut.port.put(outEx.putVal);
        expect(lIn.value, LogicValue.filled(lIn.width, LogicValue.one));
      },
      'port gets logic': (outEx, inEx) async {
        final lOut = outEx.toLogic();
        final pIn = inEx.addPort(PortDirection.input)..getsLogic(lOut);

        lOut.put(LogicValue.filled(lOut.width, LogicValue.one));
        expect(pIn.port.value, inEx.checkVal);
      },
      'inout port gets logic': (outEx, inEx) async {
        final lOut = outEx.toLogic();
        final pIn = inEx.addPort(PortDirection.inOut)..getsLogic(lOut);

        lOut.put(LogicValue.filled(lOut.width, LogicValue.one));
        expect(pIn.port.value, inEx.checkVal);
      }
    };

    for (final MapEntry(key: connTypeName, value: connTypeFun)
        in connType.entries) {
      group(connTypeName, () {
        group('1-bit', () {
          final examples = [
            PortExample('basic', Logic(), '', 0, valWidth: 1),
            PortExample('basic index', Logic(width: 8), '[3]', 3, valWidth: 1),
            PortExample('basic slice', Logic(width: 8), '[6:6]', 6,
                valWidth: 1),
            PortExample('array leaf', LogicArray([5], 1), '[2]', 2,
                valWidth: 1),
            PortExample('array leaf index', LogicArray([5], 3), '[1][1]', 4,
                valWidth: 1),
            PortExample(
                'array leaf index flat', LogicArray([5], 3), '[1][1]', 4,
                alwaysFlatLogicSource: true, valWidth: 1),
            PortExample('array leaf slice', LogicArray([5], 3), '[1][1:1]', 4,
                valWidth: 1),
            PortExample('1d array', LogicArray([1], 1), '', 0, valWidth: 1),
            PortExample('1d array flat', LogicArray([1], 1), '', 0,
                alwaysFlatLogicSource: true, valWidth: 1),
          ];

          for (final outEx in examples) {
            for (final inEx in examples) {
              test('$outEx -> $inEx', () async {
                await connTypeFun(outEx, inEx);
              });
            }
          }
        });

        group('4-bit', () {
          final examples = [
            PortExample('basic', Logic(width: 4), '', 0),
            PortExample('8-bit middle logic', Logic(width: 8), '[5:2]', 2),
            PortExample('basic 1d array 4x1', LogicArray([4], 1), '', 0),
            PortExample('basic 1d array 2x2', LogicArray([2], 2), '', 0),
            PortExample('basic 1d array 1x4', LogicArray([1], 4), '', 0),
            PortExample('2d array idx1', LogicArray([2, 4], 1), '[1]', 4),
            PortExample('2d array idx2:1', LogicArray([3, 2], 1), '[2:1]', 2),
            PortExample(
                '2d array idx2:1 flat', LogicArray([3, 2], 1), '[2:1]', 2,
                alwaysFlatLogicSource: true),
            PortExample('2d array idx3:0', LogicArray([4, 1], 1), '[3:0]', 0),
            PortExample('3d array leaf slice', LogicArray([2, 2, 2], 8),
                '[0][0][1][5:2]', 10),
            PortExample(
                'basic 1d array 2x4 leaf flat', LogicArray([2], 4), '[1]', 4,
                alwaysFlatLogicSource: true),
            PortExample('2d array idx1 slice2:1', LogicArray([2, 4], 2),
                '[1][2:1]', 10),
            PortExample('2d array idx1 slice2:1 flat', LogicArray([2, 4], 2),
                '[1][2:1]', 10,
                alwaysFlatLogicSource: true),
          ];

          for (final outEx in examples) {
            for (final inEx in examples) {
              test('$outEx -> $inEx', () async {
                await connTypeFun(outEx, inEx);
              });
            }
          }
        });
      });
    }
  });

  group('replicate punch port dimension carrying', () {
    test('full array', () {
      final subMod = BridgeModule('subMod')
        ..addInputArray('inp', null, dimensions: [4, 3], elementWidth: 2)
        ..addOutputArray('outp', dimensions: [4, 3], elementWidth: 2)
        ..addInOutArray('ino', null, dimensions: [4, 3], elementWidth: 2);
      final topMod = BridgeModule('topMod')..addSubModule(subMod);

      final topInpPortRef = subMod.port('inp').punchUpTo(topMod);
      final topInpPort = topInpPortRef.port;
      expect(topInpPort, isA<LogicArray>());
      topInpPort as LogicArray;
      expect(listEq(topInpPort.dimensions, [4, 3]), isTrue);
      expect(topInpPort.elementWidth, 2);

      final topInOutPortRef = subMod.port('ino').punchUpTo(topMod);
      final topInOutPort = topInOutPortRef.port;
      expect(topInOutPort, isA<LogicArray>());
      topInOutPort as LogicArray;
      expect(listEq(topInOutPort.dimensions, [4, 3]), isTrue);
      expect(topInOutPort.elementWidth, 2);

      final topOutpPortRef = subMod.port('outp').punchUpTo(topMod);
      final topOutpPort = topOutpPortRef.port;
      expect(topOutpPort, isA<LogicArray>());
      topOutpPort as LogicArray;
      expect(listEq(topOutpPort.dimensions, [4, 3]), isTrue);
      expect(topOutpPort.elementWidth, 2);
    });

    test('array subset keeps partial array', () {
      final subMod = BridgeModule('subMod')
        ..addInputArray('inp', null, dimensions: [4, 3], elementWidth: 2)
        ..addInOutArray('ino', null, dimensions: [4, 3], elementWidth: 2)
        ..addOutputArray('outp', dimensions: [4, 3], elementWidth: 2);
      final topMod = BridgeModule('topMod')..addSubModule(subMod);

      final topInpPortRef = subMod.port('inp[2:1]').punchUpTo(topMod);
      final topInpPort = topInpPortRef.port;
      expect(topInpPort, isA<LogicArray>());
      topInpPort as LogicArray;
      expect(listEq(topInpPort.dimensions, [2, 3]), isTrue);
      expect(topInpPort.elementWidth, 2);

      final topInOutPortRef = subMod.port('ino[2:1]').punchUpTo(topMod);
      final topInOutPort = topInOutPortRef.port;
      expect(topInOutPort, isA<LogicArray>());
      topInOutPort as LogicArray;
      expect(listEq(topInOutPort.dimensions, [2, 3]), isTrue);
      expect(topInOutPort.elementWidth, 2);

      final topOutpPortRef = subMod.port('outp[1][2:1]').punchUpTo(topMod);
      final topOutpPort = topOutpPortRef.port;
      expect(topOutpPort, isA<LogicArray>());
      topOutpPort as LogicArray;
      expect(listEq(topOutpPort.dimensions, [2]), isTrue);
      expect(topOutpPort.elementWidth, 2);
    });
  });

  group('replicate punch port types', () {
    final examples = [
      PortExample('basic', Logic(width: 4), '', 0),
      PortExample('basic index', Logic(width: 8), '[3]', 3, valWidth: 1),
      PortExample('basic slice', Logic(width: 8), '[6:6]', 6, valWidth: 1),
      PortExample('2d array idx1', LogicArray([2, 4], 1), '[1]', 4),
      PortExample('2d array idx2:1', LogicArray([3, 2], 1), '[2:1]', 2),
      PortExample('3d array leaf slice', LogicArray([2, 2, 2], 8),
          '[0][0][1][5:2]', 10),
    ];

    for (final direction in [
      PortDirection.input,
      PortDirection.output,
      PortDirection.inOut
    ]) {
      group(direction.name, () {
        for (final isMultiLevel in [true, false]) {
          group('multiLevel=$isMultiLevel', () {
            for (final ex in examples) {
              test('$ex punchUpTo', () {
                final srcPort = ex.addPort(direction);
                final superMod = BridgeModule('supermod');

                if (isMultiLevel) {
                  superMod.addSubModule(
                      BridgeModule('midmod')..addSubModule(srcPort.module));
                } else {
                  superMod.addSubModule(srcPort.module);
                }

                srcPort.punchUpTo(superMod, newPortName: 'replicated');

                final replicatedPort = superMod.port('replicated').port;

                expect(replicatedPort.width, srcPort.portSubsetLogic.width);

                if (direction == PortDirection.output) {
                  srcPort.port.put(ex.putVal);
                  expect(replicatedPort.value.and(), LogicValue.one);
                } else if (direction == PortDirection.input) {
                  replicatedPort.put(1, fill: true);
                  expect(srcPort.port.value, ex.checkVal);
                } else {
                  replicatedPort.put(1, fill: true);
                  expect(srcPort.port.value, ex.checkVal);
                  replicatedPort.put(LogicValue.z, fill: true);
                  srcPort.port.put(ex.putVal);
                  expect(replicatedPort.value.and(), LogicValue.one);
                }
              });

              test('$ex punchDownTo', () {
                final srcPort = ex.addPort(direction);
                final leafMod = BridgeModule('leafMod');

                if (isMultiLevel) {
                  srcPort.module.addSubModule(
                      BridgeModule('midmod')..addSubModule(leafMod));
                } else {
                  srcPort.module.addSubModule(leafMod);
                }

                srcPort.punchDownTo(leafMod, newPortName: 'replicated');

                final replicatedPort = leafMod.port('replicated');

                expect(replicatedPort.width, srcPort.portSubsetLogic.width);

                if (direction == PortDirection.output) {
                  replicatedPort.port.put(1, fill: true);
                  expect(srcPort.port.value, ex.checkVal);
                } else if (direction == PortDirection.input) {
                  srcPort.port.put(ex.putVal);
                  expect(replicatedPort.port.value.and(), LogicValue.one);
                } else {
                  replicatedPort.port.put(1, fill: true);
                  expect(srcPort.port.value, ex.checkVal);
                  replicatedPort.port.put(LogicValue.z, fill: true);
                  srcPort.port.put(ex.putVal);
                  expect(replicatedPort.port.value.and(), LogicValue.one);
                }
              });
            }
          });
        }
      });
    }
  });
}
