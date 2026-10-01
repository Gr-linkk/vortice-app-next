import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';

const root = fileURLToPath(new URL('../../', import.meta.url));
const runtimeFiles = ['AGENT-CLI.md', 'agent-cli/cli.mjs', 'agent-cli/client.mjs',
  'agent-cli/contract.mjs', 'agent-cli/transport.mjs',
  'agent-cli/distribution/entry.mjs', 'bin/vortice-agent'];
const messages = Object.freeze({
  bundle_invalid: 'This CLI package is incomplete or changed. Extract a verified package again. Nothing was sent.',
  connection_invalid: 'Connection settings are not valid for this client. Copy current settings from Agent connections. Nothing was sent.',
  connection_unsafe: 'Use a private connection settings file owned by your account, with mode 0600 inside its canonical mode 0700 directory. Nothing was sent.',
});
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const exact = (value, keys) => object(value) && Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k));
class SetupError extends Error { constructor(code) { super(code); this.code = code; } }
const need = (condition, code) => { if (!condition) throw new SetupError(code); };
function failure(code) {
  return {protocol_version: 1, request_id: null, ok: false,
    error: {code, message: messages[code] ?? messages.bundle_invalid, retryable: false, outcome: 'not_sent'}};
}
function regularRead(file, maximum, code, {privateFile = false, sizeCode = code} = {}) {
  let fd;
  try {
    const prior = fs.lstatSync(file);
    need(prior.isFile() && !prior.isSymbolicLink() && prior.nlink === 1, code);
    const mode = prior.mode & 0o7777;
    need(privateFile ? mode === 0o600 && prior.uid === process.getuid() :
      (mode & 0o7022) === 0 && [0, process.getuid()].includes(prior.uid), code);
    need(prior.size <= maximum, sizeCode);
    fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    const opened = fs.fstatSync(fd);
    need(opened.dev === prior.dev && opened.ino === prior.ino && opened.size === prior.size &&
      opened.mode === prior.mode && opened.uid === prior.uid && opened.nlink === 1, code);
    const bytes = Buffer.alloc(opened.size);
    let offset = 0;
    while (offset < bytes.length) {
      const count = fs.readSync(fd, bytes, offset, bytes.length - offset, offset);
      need(count > 0, code); offset += count;
    }
    const after = fs.fstatSync(fd), current = fs.lstatSync(file);
    need(after.size === opened.size && after.mtimeMs === opened.mtimeMs && after.ctimeMs === opened.ctimeMs &&
      current.dev === opened.dev && current.ino === opened.ino && current.mode === opened.mode &&
      current.uid === opened.uid && current.nlink === 1, code);
    return bytes;
  } catch (error) {
    if (error instanceof SetupError) throw error;
    throw new SetupError(code);
  } finally { if (fd !== undefined) fs.closeSync(fd); }
}
// JSON.parse establishes syntax; this small scanner additionally rejects duplicate
// object keys, including escaped spellings, rather than silently choosing one.
function uniqueJson(bytes, code) {
  try {
    const text = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
    const value = JSON.parse(text), stack = [];
    for (let i = 0; i < text.length; i++) {
      const char = text[i];
      if (char === '{' || char === '[') {
        stack.push({object: char === '{', key: true, names: new Set()});
        need(stack.length <= 8, code);
      } else if (char === '}' || char === ']') stack.pop();
      else if (char === ',') { if (stack.at(-1)?.object) stack.at(-1).key = true; }
      else if (char === '"') {
        const start = i;
        for (++i; i < text.length; i++) {
          if (text[i] === '\\') i++;
          else if (text[i] === '"') break;
        }
        const context = stack.at(-1);
        if (context?.object && context.key) {
          const key = JSON.parse(text.slice(start, i + 1));
          need(!context.names.has(key), code); context.names.add(key); context.key = false;
        }
      }
    }
    return value;
  } catch (error) {
    if (error instanceof SetupError) throw error;
    throw new SetupError(code);
  }
}
function verifyCodeLocation() {
  const directory = (file, ancestor = false) => {
    const info = fs.lstatSync(file), mode = info.mode & 0o7777;
    need(info.isDirectory() && !info.isSymbolicLink() &&
      [0, process.getuid()].includes(info.uid) && fs.realpathSync(file) === file &&
      !(mode & (ancestor ? 0o6000 : 0o7000)) &&
      (!(mode & 0o022) || ancestor && (mode & 0o1000)), 'bundle_invalid');
  };
  const packageRoot = path.resolve(root);
  for (const name of [packageRoot, path.join(packageRoot, 'bin'),
    path.join(packageRoot, 'agent-cli'), path.join(packageRoot, 'agent-cli/distribution')]) directory(name);
  for (let name = path.dirname(packageRoot);; name = path.dirname(name)) {
    directory(name, true);
    if (name === path.dirname(name)) break;
  }
}
function verifyBundle() {
  verifyCodeLocation();
  const manifest = uniqueJson(regularRead(path.join(root, 'agent-cli/distribution/bundle.json'), 16 * 1024, 'bundle_invalid'), 'bundle_invalid');
  need(exact(manifest, ['package_format', 'protocol_version', 'client_version', 'client_source_revision',
    'application_source_revision', 'application_archive_sha256', 'files']) &&
    manifest.package_format === 'vortice-linux-cli-v1' && manifest.protocol_version === 1 &&
    manifest.client_version === '0.1.0' && /^[0-9a-f]{40}$/.test(manifest.client_source_revision) &&
    /^[0-9a-f]{40}$/.test(manifest.application_source_revision) &&
    /^[0-9a-f]{64}$/.test(manifest.application_archive_sha256) && exact(manifest.files, runtimeFiles), 'bundle_invalid');
  for (const name of runtimeFiles) {
    const expected = manifest.files[name];
    need(exact(expected, ['sha256', 'bytes', 'mode']) && /^[0-9a-f]{64}$/.test(expected.sha256) &&
      Number.isInteger(expected.bytes) && expected.bytes > 0 && expected.bytes <= 512 * 1024 &&
      expected.mode === (name === 'bin/vortice-agent' ? 0o755 : 0o644), 'bundle_invalid');
    const file = path.join(root, name);
    need(fs.realpathSync(file) === file, 'bundle_invalid');
    const bytes = regularRead(file, 512 * 1024, 'bundle_invalid');
    need(bytes.length === expected.bytes && createHash('sha256').update(bytes).digest('hex') === expected.sha256, 'bundle_invalid');
  }
  return manifest;
}
function connectionArguments(argv, contract) {
  const values = [...argv], indices = values.flatMap((v, i) => v === '--connection' ? [i] : []);
  if (!indices.length) return values;
  need(indices.length === 1 && !values.some(v => ['--socket', '--workspace', '--company', '--device'].includes(v)), 'connection_invalid');
  const index = indices[0], file = values[index + 1];
  need(typeof file === 'string' && path.isAbsolute(file) && !file.includes('\0'), 'connection_invalid');
  let parent;
  try {
    const directory = path.dirname(file), before = fs.lstatSync(directory);
    need(before.isDirectory() && !before.isSymbolicLink() && before.uid === process.getuid() &&
      (before.mode & 0o7777) === 0o700 && fs.realpathSync(directory) === directory, 'connection_unsafe');
    const content = regularRead(file, 16 * 1024, 'connection_unsafe',
      {privateFile: true, sizeCode: 'connection_invalid'});
    parent = fs.lstatSync(directory);
    need(parent.dev === before.dev && parent.ino === before.ino && parent.mode === before.mode &&
      parent.uid === before.uid && fs.realpathSync(directory) === directory, 'connection_unsafe');
    const settings = uniqueJson(content, 'connection_invalid');
    need(exact(settings, ['protocol_version', 'socket_path', 'scope', 'token_environment']) &&
      settings.protocol_version === 1 && settings.token_environment === 'VORTICE_LOCAL_AGENT_TOKEN', 'connection_invalid');
    try { contract.validateScope(settings.scope); contract.validateSocketPath(settings.socket_path); }
    catch { throw new SetupError('connection_invalid'); }
    need(Buffer.from(settings.socket_path, 'utf8').toString('utf8') === settings.socket_path, 'connection_invalid');
    values.splice(index, 2);
    return [...values, '--socket', settings.socket_path, '--workspace', settings.scope.workspace_id,
      '--company', settings.scope.company_id, '--device', settings.scope.device_id];
  } catch (error) {
    if (error instanceof SetupError) throw error;
    throw new SetupError('connection_unsafe');
  }
}
async function main(argv) {
  let manifest;
  try { manifest = verifyBundle(); } catch { return failure('bundle_invalid'); }
  let cli, contract;
  try { [cli, contract] = await Promise.all([import('../cli.mjs'), import('../contract.mjs')]); }
  catch { return failure('bundle_invalid'); }
  if (contract.PROTOCOL_VERSION !== manifest.protocol_version ||
      cli.help?.protocol_version !== manifest.protocol_version || cli.help?.version !== manifest.client_version) {
    return failure('bundle_invalid');
  }
  if (argv.length === 0 || argv.length === 1 && ['help', '--help', '--version'].includes(argv[0])) {
    const {status, ...help} = cli.help;
    return {...help, ok: true, status: 'packaged_client', package_format: manifest.package_format,
      client_source_revision: manifest.client_source_revision, runtime_version: process.versions.node,
      runtime_requirement: 'Already installed compatible Node 22 or newer; no runtime is bundled.',
      connection_option: '--connection /absolute/private/connection.json supplies all required scope/socket options; copied from Agent connections',
      setup: ['Open the office app and explicitly enable Agent connections.',
        'Create a scoped connection with finite expiry. Supply its credential privately through the agent host environment.',
        'Copy current token-free settings into a private file. Recopy after the office service restarts.'],
      example: 'bin/vortice-agent work list --connection /private/connection.json'};
  }
  let args;
  try { args = connectionArguments(argv, contract); }
  catch (error) { return failure(error instanceof SetupError ? error.code : 'connection_invalid'); }
  let parsed;
  try { parsed = cli.parseArgs(args, '', true); }
  catch (error) { return contract.safeError(error); }
  if (parsed.intent.command === 'capabilities') return cli.run(args);
  const scopeFlags = ['--socket', parsed.socketPath, '--workspace', parsed.intent.scope.workspace_id,
    '--company', parsed.intent.scope.company_id, '--device', parsed.intent.scope.device_id];
  const capabilities = await cli.run(['capabilities', ...scopeFlags]);
  const keyIndex = args.indexOf('--operation'), operation = keyIndex >= 0 ? args[keyIndex + 1] : undefined;
  if (!capabilities.ok) {
    // This read may be uncertain, but the user's requested command has not run.
    return {...capabilities, error: {...capabilities.error, outcome: 'not_sent',
      ...(operation ? {idempotency_key: operation} : {})}};
  }
  const command = parsed.intent.command;
  if (!capabilities.result.commands.includes(command)) return contract.safeError(new contract.CliError('unsupported_command'), capabilities.request_id, operation);
  if (command === 'proposals.create' && !capabilities.result.proposal_types.includes('inspection.notes')) {
    return contract.safeError(new contract.CliError('unsupported_proposal'), capabilities.request_id, operation);
  }
  return cli.run(args);
}

let result;
try { result = await main(process.argv.slice(2)); }
catch {
  // A late unexpected failure cannot establish that a requested write rolled back.
  result = {protocol_version: 1, request_id: null, ok: false,
    error: {code: 'internal_error', message: 'The command could not be completed.', retryable: false, outcome: 'unknown'}};
}
process.stdout.write(`${JSON.stringify(result)}\n`);
process.exitCode = result.ok ? 0 : result.error.outcome === 'unknown' ? 3 :
  ['bundle_invalid', 'connection_invalid', 'connection_unsafe', 'invalid_input'].includes(result.error.code) ? 2 : 1;
