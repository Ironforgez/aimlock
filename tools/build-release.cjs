const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const luamin = require('luamin');
const luaparse = require('luaparse');

const root = path.resolve(__dirname, '..');
const checkOnly = process.argv.includes('--check');
const modules = ['config', 'random', 'engine', 'statistics', 'simulation', 'integration'];
const entryPath = 'moonloader/AimLock.lua';
const sourcePaths = [entryPath, ...modules.map(name =>
  `moonloader/lib/arfie_hit_distribution/${name}.lua`)];
const sha256 = value => crypto.createHash('sha256').update(value).digest('hex');

function build() {
  const sources = sourcePaths.map(sourcePath => {
    const bytes = fs.readFileSync(path.join(root, sourcePath));
    return { path: sourcePath, sha256: sha256(bytes), text: bytes.toString('latin1').replace(/\r\n/g, '\n') };
  });
  const entry = sources[0].text;
  const versionMatch = entry.match(/^script_version\(['"](\d+\.\d+\.\d+)['"]\)/m);
  if (!versionMatch) throw new Error('Source must declare a numeric script_version.');
  const version = versionMatch[1];
  const sourceManifest = sources.map(({ path: sourcePath, sha256: hash }) => ({ path: sourcePath, sha256: hash }));
  const sourceSetHash = sha256(JSON.stringify(sourceManifest));

  let bundle = `local factories, loaded = {}, {}
local function bundled_require(name)
    if loaded[name] ~= nil then return loaded[name] end
    local factory = factories[name]
    if not factory then error('Unknown bundled module: ' .. tostring(name)) end
    local value = factory(bundled_require)
    if value == nil then value = true end
    loaded[name] = value
    return value
end
`;
  for (const source of sources.slice(1)) {
    const name = `arfie_hit_distribution.${path.basename(source.path, '.lua')}`;
    bundle += `factories[${JSON.stringify(name)}] = function(require)\n${source.text}\nend\n`;
  }
  bundle += `(function(require)\n${entry}\nend)(bundled_require)\nreturn bundled_require\n`;

  const ast = luaparse.parse(bundle, {
    luaVersion: '5.1', scope: true, ranges: true, comments: false, encodingMode: 'pseudo-latin1'
  });
  let encodedStrings = 0;
  const replacements = [];
  const visited = new Set();
  function encodeStrings(node) {
    if (node === null || typeof node !== 'object' || visited.has(node)) return;
    visited.add(node);
    if (node.type === 'StringLiteral') {
      // Lua decimal escapes encode bytes, including UTF-8 bytes in future messages.
      const bytes = Buffer.from(node.value, 'latin1');
      const raw = '"' + Array.from(bytes, byte => '\\' + String(byte).padStart(3, '0')).join('') + '"';
      replacements.push({ start: node.range[0], end: node.range[1], raw });
      encodedStrings++;
    }
    for (const value of Object.values(node)) encodeStrings(value);
  }
  encodeStrings(ast);
  let encodedBundle = bundle;
  for (const replacement of replacements.sort((left, right) => right.start - left.start)) {
    encodedBundle = encodedBundle.slice(0, replacement.start) + replacement.raw
      + encodedBundle.slice(replacement.end);
  }
  const obfuscated = luamin.minify(encodedBundle);
  let outputAst;
  try {
    outputAst = luaparse.parse(obfuscated, { luaVersion: '5.1', scope: true });
  } catch (error) {
    const index = error.index || 0;
    throw new Error(`${error.message}; generated context: ${obfuscated.slice(Math.max(0, index - 90), index + 90)}`);
  }
  if (!outputAst.globals.some(node => node.name === 'main')) {
    throw new Error('MoonLoader global main hook was lost.');
  }

  const artifactPath = `moonloader/AimLock${version}.lua`;
  const header = `-- AimLock ${version} | bundled and obfuscated Lua 5.1\n`
    + `-- Source-set SHA256: ${sourceSetHash}\n`
    + '-- Install one copy only; config/AimLock.ini is required.\n';
  const artifact = header + obfuscated + '\n';
  const manifest = {
    version,
    artifact: artifactPath,
    artifact_sha256: sha256(artifact),
    source_set_sha256: sourceSetHash,
    sources: sourceManifest,
    configuration: {
      path: 'moonloader/config/AimLock.ini',
      sha256: sha256(fs.readFileSync(path.join(root, 'moonloader/config/AimLock.ini')))
    },
    modules: modules.length,
    encoded_strings: encodedStrings,
    tools: { luamin: require('luamin/package.json').version, luaparse: require('luaparse/package.json').version },
    method: 'Private module bundle, local identifier renaming, minification, decimal string escapes'
  };
  const outputs = [
    [artifactPath, artifact],
    [`moonloader/AimLock${version}.manifest.json`, JSON.stringify(manifest, null, 2) + '\n']
  ];
  for (const [outputPath, content] of outputs) {
    const absolutePath = path.join(root, outputPath);
    if (checkOnly) {
      if (fs.readFileSync(absolutePath, 'utf8') !== content) {
        throw new Error(`${outputPath} is stale; rebuild before publishing.`);
      }
    } else {
      fs.writeFileSync(absolutePath, content, 'utf8');
    }
  }
  console.log(`${checkOnly ? 'PASS' : 'Built'} ${artifactPath}: ${Buffer.byteLength(artifact)} bytes, `
    + `${modules.length} bundled modules, ${encodedStrings} encoded strings`);
  console.log(`SHA256 ${manifest.artifact_sha256}`);
}

try {
  build();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
