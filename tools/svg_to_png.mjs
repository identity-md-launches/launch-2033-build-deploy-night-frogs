// Optional deterministic preview rasterizer. Vendored resvg WASM + IBM Plex Mono.
// node tools/svg_to_png.mjs source.svg output.png [width]; source '-' reads stdin.
import {readFileSync, writeFileSync} from 'node:fs';
import {initWasm, Resvg} from './vendor/resvg-wasm/index.mjs';
await initWasm(readFileSync(new URL('./vendor/resvg-wasm/index_bg.wasm', import.meta.url)));
const font = readFileSync(new URL('./vendor/fonts/IBMPlexMono-Bold.ttf', import.meta.url));
const [source, target, width = '1000'] = process.argv.slice(2);
const renderer = new Resvg(readFileSync(source === '-' ? 0 : source), {
  fitTo: {mode: 'width', value: Number(width)},
  font: {fontBuffers: [font], defaultFontFamily: 'IBM Plex Mono', monospaceFamily: 'IBM Plex Mono', loadSystemFonts: false},
});
writeFileSync(target, renderer.render().asPng());
renderer.free();
