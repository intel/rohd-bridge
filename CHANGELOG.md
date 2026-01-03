## 0.2.1

- Fixed a bug where a confusing exception could be thrown if the logger was used but not yet configured (<https://github.com/intel/rohd-bridge/pull/32>).
- Fixed a bug where if a directory did not exist for a log file, it would crash instead of creating the necessary directory structure (<https://github.com/intel/rohd-bridge/pull/32>).
- Deprecated `logger` in `BridgeModule.buildAndGenerateRTL` in favor of using the default logger (<https://github.com/intel/rohd-bridge/pull/32>).
- Deprecated `enableDebugMesage` and `fileSink` in `RohdBridgeLogger` (<https://github.com/intel/rohd-bridge/pull/32>).

## 0.2.0

- Breaking: `PortReference.tieOff` and `BridgeModule.tieOffInterface` now accept `value` as a named argument instead of a positional argument to support additional arguments (e.g. `fill`) (<https://github.com/intel/rohd-bridge/pull/27>).
- Upgraded `ConnectionExtractor` to support identification of constant tie-offs in addition to port connections and to optionally ignore full interface connections to make some kinds of connection analysis easier (<https://github.com/intel/rohd-bridge/pull/27>).
- Fixed a bug where calling `getsLogic` on a sub-array of a port could incorrectly count the number of elements, leading to a confusing error message instead of the expected correct connection (<https://github.com/intel/rohd-bridge/pull/28>).
- Added `parentPortReference` to `SlicePortReference` to allow easier access a port reference one dimension up (<https://github.com/intel/rohd-bridge/pull/29>).
- Updates to properly support leaving unconnected ports empty in generated SystemVerilog in support of new ROHD features in <https://github.com/intel/rohd/pull/638> (<https://github.com/intel/rohd-bridge/pull/26>).

## 0.1.4

- Fixed a bug where unpacked array dimensions would be converted to packed dimensions when replicating or pulling up ports (<https://github.com/intel/rohd-bridge/pull/24>).

## 0.1.3

- Fixed a limitation where loop-back from an output to an input on the same module was illegal (<https://github.com/intel/rohd-bridge/pull/21>).

## 0.1.2

- Improved error messages and exceptions when illegal connections are made in ROHD Bridge, reducing how frequently you get a lower-level ROHD connection error.
- Added the ability to form an `internalInterface` "later", i.e. if and when it is needed for things like vertical connections with custom port maps (<https://github.com/intel/rohd-bridge/pull/11>).
- Fixed bugs related to vertical connections (parent/child) of interfaces (<https://github.com/intel/rohd-bridge/pull/9>).
- Fixed bugs and missing arguments related to `exceptPorts` in various functions when connecting and creating interfaces (<https://github.com/intel/rohd-bridge/pull/17>).

## 0.1.1

- Improved internal APIs related to JSON handling (<https://github.com/intel/rohd-bridge/pull/7>).

## 0.1.0

- Initial version of ROHD Bridge.
