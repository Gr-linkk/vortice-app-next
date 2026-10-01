import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createHash} from 'node:crypto';
import {chmod, copyFile, mkdir, mkdtemp, readFile, rename, rm, symlink, writeFile} from 'node:fs/promises';
import net from 'node:net';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

// No imports from the client under test: all observations cross the extracted
// launcher/process or private Unix protocol boundary.
export const sourceRoot = process.env.VORTICE_DIST_SOURCE_ROOT ??
  fileURLToPath(new URL('../../../../', import.meta.url));
export const token = 'synthetic-distribution-token-not-a-real-grant';
export const scope = {workspace_id: 'workspace_dist', company_id: 'company_dist', device_id: 'office_dist'};
export const operation = '11111111-1111-4111-8111-111111111111';
export const commands = ['capabilities', 'workspace.status', 'equipment.list', 'equipment.show',
  'procedures.list', 'procedures.show', 'work.list', 'work.show', 'history.list',
  'proposals.list', 'proposals.show', 'proposals.create'];
export const runtimeFiles = {
  'bin/vortice-agent': 'tools/local-agent-cli/distribution/vortice-agent',
  'agent-cli/cli.mjs': 'tools/local-agent-cli/cli.mjs',
  'agent-cli/client.mjs': 'tools/local-agent-cli/client.mjs',
  'agent-cli/contract.mjs': 'tools/local-agent-cli/contract.mjs',
  'agent-cli/transport.mjs': 'tools/local-agent-cli/transport.mjs',
  'agent-cli/distribution/entry.mjs': 'tools/local-agent-cli/distribution/entry.mjs',
  'AGENT-CLI.md': 'tools/local-agent-cli/distribution/AGENT-CLI.md',
};

export async function executeFile(executable, args, {env = {}, input = '', cwd, timeout = 15000} = {}) {
  const inherited = {...process.env};
  delete inherited.NODE_OPTIONS;
  delete inherited.NODE_PATH;
  const child = spawn(executable, args, {cwd, env: {...inherited,
    VORTICE_LOCAL_AGENT_TOKEN: token, ...env}, stdio: ['pipe', 'pipe', 'pipe']});
  let stdout = '', stderr = '', bytes = 0;
  const result = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {child.kill('SIGKILL'); reject(new Error('Synthetic launcher timed out.'));}, timeout);
    child.once('error', error => {clearTimeout(timer); reject(error);});
    for (const [stream, collect] of [[child.stdout, data => {stdout += data;}],
      [child.stderr, data => {stderr += data;}]]) {
      stream.setEncoding('utf8');
      stream.on('data', chunk => {
        bytes += Buffer.byteLength(chunk);
        if (bytes > 2 * 1024 * 1024) {
          child.kill('SIGKILL'); clearTimeout(timer); reject(new Error('Synthetic launcher output exceeded its bound.'));
        } else collect(chunk);
      });
    }
    child.once('close', (status, signal) => {clearTimeout(timer); resolve({status, signal, stdout, stderr});});
    child.stdin.on('error', () => {});
    child.stdin.end(input);
  });
  return result;
}

export async function bundleFixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'vortice-dist-test-'));
  await chmod(root, 0o700);
  t.after(() => rm(root, {recursive: true, force: true}));
  let bundle = join(root, 'original extraction');
  const unrelated = join(root, 'unrelated caller');
  await mkdir(unrelated, {mode: 0o700});
  const inventory = {};
  for (const [relative, source] of Object.entries(runtimeFiles)) {
    const destination = join(bundle, relative);
    await mkdir(dirname(destination), {recursive: true, mode: 0o755});
    await copyFile(join(sourceRoot, source), destination);
    const mode = relative === 'bin/vortice-agent' ? 0o755 : 0o644;
    await chmod(destination, mode);
    const bytes = await readFile(destination);
    inventory[relative] = {sha256: createHash('sha256').update(bytes).digest('hex'), bytes: bytes.length, mode};
  }
  const metadata = {package_format: 'vortice-linux-cli-v1', protocol_version: 1,
    client_version: '0.1.0', client_source_revision: '6'.repeat(40),
    application_source_revision: 'b'.repeat(40), application_archive_sha256: 'a'.repeat(64), files: inventory};
  async function saveMetadata() {
    const path = join(bundle, 'agent-cli/distribution/bundle.json');
    await writeFile(path, JSON.stringify(metadata), {mode: 0o644});
    await chmod(path, 0o644);
  }
  await saveMetadata();
  const moved = join(root, 'moved package 空间 café');
  await rename(bundle, moved); bundle = moved;
  const fixture = {root, bundle, unrelated, metadata, saveMetadata,
    launcher: join(bundle, 'bin/vortice-agent'),
    invoke: (args, options = {}) => executeFile(join(bundle, 'bin/vortice-agent'), args,
      {cwd: unrelated, ...options})};
  return fixture;
}

export async function connectionFile(fixture, socketPath, value = {}) {
  const parent = join(fixture.root, 'private settings');
  await mkdir(parent, {recursive: true, mode: 0o700});
  await chmod(parent, 0o700);
  const file = join(parent, 'office connection 空间.json');
  const settings = {protocol_version: 1, socket_path: socketPath, scope: {...scope},
    token_environment: 'VORTICE_LOCAL_AGENT_TOKEN', ...value};
  await writeFile(file, JSON.stringify(settings), {mode: 0o600});
  await chmod(file, 0o600);
  return {file, parent, settings};
}

export function explicit(socketPath) {
  return ['--socket', socketPath, '--workspace', scope.workspace_id,
    '--company', scope.company_id, '--device', scope.device_id];
}

export function response(request, result) {
  return {protocol_version: 1, request_id: request.request_id, scope: request.scope,
    ok: true, result, meta: {source: 'local', freshness: 'local_snapshot',
      observed_at: '2026-10-01T00:00:00.000Z', local_revision: '1'.repeat(64), complete: true,
      synced: {verified: false, reason: 'no_fresh_transfer_proof'}}};
}

export function standardReply(request) {
  if (request.command === 'capabilities') return response(request,
    {commands: [...commands], proposal_types: ['inspection.notes']});
  if (request.command.endsWith('.list')) return response(request,
    {items: [], count: 0, next_cursor: null});
  if (request.command === 'proposals.create') return response(request, {item: {
    proposal_id: 'synthetic_proposal', ...request.args, status: 'pending_human_review',
    requires_human_review: true, applied: false}});
  if (request.command === 'work.show') return response(request, {item: {job_id: request.args.job_id}});
  throw new Error('Synthetic fixture requires a declared response.');
}

export async function protocolFixture(t, directory, handler = (socket, request) =>
  socket.end(`${JSON.stringify(standardReply(request))}\n`)) {
  const parent = join(directory, 'unix');
  await mkdir(parent, {mode: 0o700});
  const socketPath = join(parent, 's.sock');
  assert(Buffer.byteLength(socketPath) <= 100);
  const received = [], clients = new Set();
  const server = net.createServer(socket => {
    clients.add(socket); socket.once('close', () => clients.delete(socket));
    socket.on('error', () => {});
    let data = '';
    socket.on('data', chunk => {
      data += chunk.toString('utf8');
      if (!data.includes('\n')) return;
      socket.removeAllListeners('data');
      const request = JSON.parse(data.slice(0, data.indexOf('\n')));
      received.push(request); handler(socket, request, received);
    });
  });
  t.after(async () => {
    for (const socket of clients) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  });
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(socketPath, resolve);});
  await chmod(socketPath, 0o600);
  return {socketPath, received};
}

export function safeFailure(result, code, outcome = 'not_sent', exit = 2) {
  assert.equal(result.status, exit);
  assert.equal(result.stderr, '');
  const lines = result.stdout.trim().split('\n');
  assert.equal(lines.length, 1);
  const value = JSON.parse(lines[0]);
  assert.equal(value.ok, false);
  assert.equal(value.error.code, code);
  assert.equal(value.error.outcome, outcome);
  assert(!result.stdout.includes(token));
  assert(!/Error:|stack|node:internal|\.mjs:\d/.test(result.stdout));
  return value;
}

export async function fakeRuntime(fixture, body) {
  const bin = join(fixture.root, 'runtime bin');
  await mkdir(bin, {recursive: true, mode: 0o700});
  for (const name of ['sh', 'bash', 'env', 'dirname', 'readlink']) {
    await symlink(`/usr/bin/${name}`, join(bin, name)).catch(error => {
      if (error.code !== 'EEXIST') throw error;
    });
  }
  if (body !== null) await writeFile(join(bin, 'node'), `#!/bin/sh\n${body}\n`, {mode: 0o700});
  return bin;
}
