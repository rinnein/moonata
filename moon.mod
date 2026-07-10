// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "rinnein/moonata"

version = "0.8.0"

readme = "README.mbt.md"

repository = "https://github.com/rinnein/moonata"

license = "Apache-2.0"

keywords = [ ]

preferred_target = "wasm-gc"

description = "JSONata rewritten in moonbit."

import {
  "moonbitlang/regexp@0.3.5",
  "moonbitlang/async@0.20.0",
  "moonbitlang/x@0.4.46",
}
