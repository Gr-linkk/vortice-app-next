import assert from 'node:assert/strict';
import {chmod, lstat, readFile, rename, symlink, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {bundleFixture, explicit, fakeRuntime, operation, protocolFixture,
  safeFailure, token} from './harness.mjs';

const shellQuote = value => `'${value.replaceAll("'", "'\\''")}'`;
const packageDirectories = ['', 'bin', 'agent-cli', 'agent-cli/distribution'];
const proposal = JSON.stringify({type: 'inspection.notes', job_id: 'job_a',
  expected_document_hash: 'a'.repeat(64), notes: 'Synthetic directory refusal.'});

// This forwarding shim observes only whether the public fixture token exists.
// The actual version, inline builtin preflight, and entry use installed Node;
// this is not a simulation of executing on the minimum supported version.
async function runtimeTrace(fixture) {
  const file = join(fixture.root, 'runtime-phases.txt');
  const bin = await fakeRuntime(fixture, `
case "$1" in --version) phase=version ;; -e) phase=preflight ;; *) phase=entry ;; esac
if [ -z "\${VORTICE_LOCAL_AGENT_TOKEN:-}" ]; then credential=empty; else credential=present; fi
printf '%s:%s\\n' "$phase" "$credential" >> ${shellQuote(file)}
exec ${shellQuote(process.execPath)} "$@"`);
  return {env: {PATH: bin}, read: async () => (await readFile(file, 'utf8')).trim().split('\n')};
}

async function refusedBeforeEntry(fixture, server, trace, args, options = {}) {
  safeFailure(await fixture.invoke(args, {...options, env: trace.env}), 'bundle_invalid');
  assert.deepEqual(await trace.read(), ['version:empty', 'preflight:empty']);
  assert.equal(server.received.length, 0);
}

test('writable package directories refuse before credential-bearing entry and any command', async t => {
  const commands = [
    ['help', ['--help']],
    ['capabilities', ['capabilities']],
    ['read', ['work', 'list']],
    ['proposal', ['proposals', 'create', '--operation', operation, '--input', '-']],
  ];
  for (const relative of packageDirectories) for (const [name, command] of commands) {
    await t.test(`${relative || 'package root'}: ${name}`, async sub => {
      const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
      const trace = await runtimeTrace(fixture), directory = join(fixture.bundle, relative);
      await chmod(directory, 0o777);
      const args = name === 'help' ? command : [...command, ...explicit(server.socketPath)];
      await refusedBeforeEntry(fixture, server, trace, args, {input: proposal});
      assert.equal((await lstat(directory)).mode & 0o7777, 0o777);
    });
  }
});

test('unsafe package directory cannot expose a token to a replaced entry canary', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  const trace = await runtimeTrace(fixture), marker = join(fixture.root, 'entry-observed-credential');
  const entry = join(fixture.bundle, 'agent-cli/distribution/entry.mjs');
  await writeFile(entry, `import fs from 'node:fs';\nfs.writeFileSync(${JSON.stringify(marker)}, process.env.VORTICE_LOCAL_AGENT_TOKEN ? 'present' : 'empty');\n`);
  await chmod(join(fixture.bundle, 'agent-cli'), 0o777);
  await refusedBeforeEntry(fixture, server, trace, ['work', 'list', ...explicit(server.socketPath)]);
  await assert.rejects(readFile(marker), {code: 'ENOENT'});
});

test('nonsticky writable extraction ancestors refuse without repairing permissions', async t => {
  for (const mode of [0o777, 0o775, 0o757]) await t.test(mode.toString(8), async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const trace = await runtimeTrace(fixture);
    await chmod(fixture.root, mode);
    await refusedBeforeEntry(fixture, server, trace, ['work', 'list', ...explicit(server.socketPath)]);
    assert.equal((await lstat(fixture.root)).mode & 0o7777, mode);
  });
});

test('package directories reject special permission bits including sticky writable mode', async t => {
  for (const mode of [0o1777, 0o1755, 0o2755, 0o4755]) await t.test(mode.toString(8), async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const trace = await runtimeTrace(fixture), directory = join(fixture.bundle, 'agent-cli');
    await chmod(directory, mode);
    await refusedBeforeEntry(fixture, server, trace, ['capabilities', ...explicit(server.socketPath)]);
    assert.equal((await lstat(directory)).mode & 0o7777, mode);
  });
});

test('symlink directories inside the package refuse before entry', async t => {
  for (const relative of packageDirectories.slice(1)) await t.test(relative, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const trace = await runtimeTrace(fixture), directory = join(fixture.bundle, relative);
    const target = `${directory}-original`;
    await rename(directory, target); await symlink(target, directory);
    safeFailure(await fixture.invoke(['work', 'list', ...explicit(server.socketPath)], {env: trace.env}), 'bundle_invalid');
    // Shell rejection may occur before inline Node is needed. Neither permitted
    // probe may carry the token, and the entry must never be started.
    const phases = await trace.read();
    assert(phases.length >= 1 && phases.length <= 2);
    assert(phases.every(value => value === 'version:empty' || value === 'preflight:empty'));
    assert.equal(server.received.length, 0); assert((await lstat(directory)).isSymbolicLink());
  });
});

test('a supplied extraction alias can use its safe canonical physical package', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  const trace = await runtimeTrace(fixture), target = `${fixture.bundle}-physical`;
  await rename(fixture.bundle, target); await symlink(target, fixture.bundle);
  const result = await fixture.invoke(['work', 'list', ...explicit(server.socketPath)], {env: trace.env});
  assert.equal(result.status, 0); assert.equal(result.stderr, '');
  assert.deepEqual(await trace.read(), ['version:empty', 'preflight:empty', 'entry:present']);
  assert.deepEqual(server.received.map(value => value.command), ['capabilities', 'work.list']);
  assert((await lstat(fixture.bundle)).isSymbolicLink());
});

test('trusted sticky ancestors and restrictive package directories retain normal dispatch', async t => {
  for (const [ancestor, directories] of [[0o700, 0o755], [0o755, 0o700], [0o1777, 0o755]]) {
    await t.test(`${ancestor.toString(8)} ancestor / ${directories.toString(8)} package`, async sub => {
      const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
      const trace = await runtimeTrace(fixture);
      await chmod(fixture.root, ancestor);
      for (const relative of packageDirectories) await chmod(join(fixture.bundle, relative), directories);
      const result = await fixture.invoke(['work', 'list', ...explicit(server.socketPath)], {env: trace.env});
      assert.equal(result.status, 0); assert.equal(result.stderr, '');
      assert.deepEqual(await trace.read(), ['version:empty', 'preflight:empty', 'entry:present']);
      assert.deepEqual(server.received.map(value => value.command), ['capabilities', 'work.list']);
      assert(server.received.every(value => value.credential.token === token));
      assert.equal((await lstat(fixture.root)).mode & 0o7777, ancestor);
      for (const relative of packageDirectories) assert.equal((await lstat(join(fixture.bundle, relative))).mode & 0o7777, directories);
    });
  }
});
