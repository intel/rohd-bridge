## 0.2.0

- Breaking: `PortReference.tieOff` and `BridgeModule.tieOffInterface` now accept `value` as a named argument instead of a positional argument to support additional arguments (e.g. `fill`).

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
