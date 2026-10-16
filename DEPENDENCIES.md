# Vendored dependencies

Everything needed by Foundry is in this repository. No submodules or package manager resolution is used at build time.

| Files | Pinned source | License |
| --- | --- | --- |
| `lib/openzeppelin-contracts/contracts/` | [OpenZeppelin Contracts v5.0.2](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.0.2/contracts) | `lib/openzeppelin-contracts/LICENSE`, MIT |
| `lib/forge-std/src/` | [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7/src) | `lib/forge-std/LICENSE-MIT` and `LICENSE-APACHE` |
| `tools/vendor/resvg-wasm/` | [@resvg/resvg-wasm 2.6.2](https://www.npmjs.com/package/@resvg/resvg-wasm/v/2.6.2), published WASM and JS | `tools/vendor/resvg-wasm/LICENSE`, MPL-2.0 |
| `tools/vendor/fonts/IBMPlexMono-Bold.ttf` | [Google Fonts IBM Plex Mono](https://github.com/google/fonts/tree/main/ofl/ibmplexmono), exact bytes vendored | `tools/vendor/fonts/OFL.txt`, OFL-1.1 |

OpenZeppelin and forge-std source files are unmodified. Art is original code-native SVG, authored in `tools/build_art.py`; there is no downloaded reference artwork. The minimal VRF coordinator interface is an independently written declaration of the official Chainlink v2.5 request ABI. It intentionally exposes no coordinator migration or additional ownership authority.

Preview tooling requires Python 3 and Node.js; the binary rasterizer is WebAssembly, not a Solidity compiler. Foundry requires only its normal runtime and the version-pinned Solidity compiler supplied by the verification environment. No compiler binary is vendored.
