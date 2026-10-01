const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {chromium} = require('playwright');
const {buildSync} = require('esbuild');

function verify(api, cases, equal, ok) {
  let tensorCount = 0;
  for (const row of cases) {
    const bytes = Uint8Array.from(row.hex.match(/../g) || [], c => parseInt(c, 16));
    const padded = new Uint8Array(bytes.length + 14);
    padded.set(bytes, 7);
    const view = padded.subarray(7, 7 + bytes.length);
    const reader = api.open(view);
    const result = JSON.parse(api.describe(reader));
    equal(result, row.expected, row.name);
    view.fill(0);
    equal(JSON.parse(api.describe(reader)), row.expected, row.name + ': input ownership');
    if (result.ok) for (const tensor of result.tensors) {
      tensorCount++;
      const copy = api.copy(reader, tensor.name);
      ok(copy instanceof Uint8Array, 'Uint8Array output');
      equal(Array.from(copy), Array.from(Uint8Array.from(tensor.data.match(/../g) || [], c => parseInt(c,16))), tensor.name);
      copy.fill(0);
      equal(Array.from(api.copy(reader, tensor.name)), Array.from(Uint8Array.from(tensor.data.match(/../g) || [], c => parseInt(c,16))), row.name + ': output ownership');
    }
  }
  const invalid = [null, {}, 'abc', new Uint16Array(2), new DataView(new ArrayBuffer(8))];
  if (typeof SharedArrayBuffer !== 'undefined') invalid.push(new Uint8Array(new SharedArrayBuffer(8)));
  if (typeof structuredClone === 'function') {
    const view = new Uint8Array(8);
    structuredClone(view.buffer, {transfer: [view.buffer]});
    invalid.push(view);
  }
  if (typeof ArrayBuffer.prototype.resize === 'function') invalid.push(new Uint8Array(new ArrayBuffer(8, {maxByteLength:16})));
  for (const view of invalid) equal(JSON.parse(api.describe(api.open(view))), {ok:false,kind:'invalid_argument',path:null,byte_offset:null}, 'invalid buffer');
  // All possible raw bytes, including invalid UTF-8, must survive the adapter.
  const h = new TextEncoder().encode('{"é☃":{"dtype":"U8","shape":[256],"data_offsets":[0,256]}}');
  const data = new Uint8Array(8 + h.length + 256);
  new DataView(data.buffer).setBigUint64(0, BigInt(h.length), true);
  data.set(h, 8);
  for (let i=0; i<256; i++) data[8+h.length+i] = i;
  const reader = api.open(data);
  equal(Array.from(api.copy(reader, 'é☃')), Array.from({length:256}, (_,i)=>i), 'all byte values');
  return {cases: cases.length, tensorCount, invalidBuffers:invalid.length,
    maxStringLength:api.maxStringLength, maxInt:api.maxInt};
}

async function main() {
  const backend = process.argv[2];
  assert(['jsoo','melange'].includes(backend));
  const root = path.resolve(__dirname, '..');
  const cases = JSON.parse(fs.readFileSync(path.join(root,'.cache/javascript/corpus.json')));
  const work = path.join(root,'.cache/javascript',backend);
  const entry = path.join(work, backend === 'jsoo' ? '_build/default/main.bc.js' : '_build/default/out/main.js');
  const bundle = path.join(work,'browser.js');
  if (backend === 'jsoo') fs.copyFileSync(entry, bundle);
  else buildSync({entryPoints:[entry], outfile:bundle, bundle:true, platform:'browser', format:'iife', target:'es2021'});
  const code = fs.readFileSync(bundle,'utf8');
  // Run the browser bundle in Node too; the reader has no Node I/O dependency.
  const api = backend === 'jsoo' ? require(entry).safetensors :
    (vm.runInThisContext(code, {filename:bundle}), globalThis.safetensors);
  const node = verify(api, cases, assert.deepStrictEqual, assert.ok);
  const first = cases.find(c => c.expected.ok && c.expected.tensors.length);
  const buffer = Buffer.from(first.hex, 'hex');
  assert.deepStrictEqual(JSON.parse(api.describe(api.open(buffer))), first.expected);
  const foreign = vm.runInNewContext('new Uint8Array('+JSON.stringify(Array.from(buffer))+')');
  assert.deepStrictEqual(JSON.parse(api.describe(api.open(foreign))), first.expected);
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    await page.route('**/*', route => route.abort());
    await page.addScriptTag({content:code});
    const result = await page.evaluate(({cases, source}) => {
      const equal = (a,b,label) => {
        const canonical = v => v && typeof v === 'object' ? (Array.isArray(v) ? v.map(canonical) :
          Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])]))) : v;
        if (JSON.stringify(canonical(a)) !== JSON.stringify(canonical(b))) throw Error(label);
      };
      const ok = (v,label) => {if (!v) throw Error(label);};
      return (0,eval)('('+source+')')(globalThis.safetensors,cases,equal,ok);
    }, {cases, source:verify.toString()});
    const report = {backend, nodeVersion:process.version, browserVersion:browser.version(),
      node, browser:result, browserBundleBytes:fs.statSync(bundle).size,
      peakRssBytes:process.resourceUsage().maxRSS*1024,
      memoryMeasurement:'Node process peak RSS, includes corpus/hex comparison and bundling; not intrinsic reader overhead'};
    fs.mkdirSync(path.join(root,'.cache/reports'),{recursive:true});
    fs.writeFileSync(path.join(root,'.cache/reports',backend+'.json'), JSON.stringify(report,null,2)+'\n');
    console.log(JSON.stringify(report));
  } finally {await browser.close();}
}
main().catch(e => {console.error(e); process.exit(1);});
