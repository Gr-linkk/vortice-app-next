import assert from 'node:assert/strict';
import {chmod, link, lstat, readFile, rename, symlink, unlink, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {bundleFixture, commands, connectionFile, explicit, fakeRuntime, operation,
  protocolFixture, response, safeFailure, scope, standardReply, token} from './harness.mjs';

test('moved Unicode/space extraction works from unrelated cwd with no source imports', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  const result = await fixture.invoke(['work', 'list', ...explicit(server.socketPath), '--limit', '3']);
  assert.equal(result.status, 0); assert.equal(result.stderr, '');
  assert.equal(JSON.parse(result.stdout).ok, true);
  assert.deepEqual(server.received.map(r => r.command), ['capabilities', 'work.list']);
  assert.deepEqual(server.received[1].args, {limit: 3});
  assert.deepEqual(server.received.map(r => r.scope), [{...scope}, {...scope}]);
  assert(server.received.every(r => r.credential.token === token));
  assert(!result.stdout.includes(fixture.root));
  for (const name of ['cli', 'client', 'contract', 'transport']) {
    const source = await readFile(join(fixture.bundle, `agent-cli/${name}.mjs`), 'utf8');
    assert(!source.includes(fixture.root));
  }
});

test('exact copied connection settings dispatch the same bounded scoped command', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  const settings = await connectionFile(fixture, server.socketPath);
  const result = await fixture.invoke(['work', 'list', '--connection', settings.file, '--job', 'job_a', '--limit', '1']);
  assert.equal(result.status, 0); assert.equal(result.stderr, '');
  assert.deepEqual(server.received.map(r => r.command), ['capabilities', 'work.list']);
  assert.deepEqual(server.received[1].args, {limit: 1, job_id: 'job_a'});
  assert.equal(await readFile(settings.file, 'utf8'), JSON.stringify(settings.settings));
});

test('capabilities command does not recursively perform a capabilities preflight', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  const result = await fixture.invoke(['capabilities', ...explicit(server.socketPath)]);
  assert.equal(result.status, 0);
  assert.deepEqual(server.received.map(r => r.command), ['capabilities']);
});

test('help is available from extracted launcher without an endpoint or token', async t => {
  const fixture = await bundleFixture(t);
  const result = await fixture.invoke(['--help'], {env: {VORTICE_LOCAL_AGENT_TOKEN: ''}});
  assert.equal(result.status, 0); assert.equal(result.stderr, '');
  assert.equal(JSON.parse(result.stdout).ok, true);
});

test('missing runtime returns fixed JSON before loading client code', async t => {
  const fixture = await bundleFixture(t), bin = await fakeRuntime(fixture, null);
  const result = await fixture.invoke(['--help'], {env: {PATH: bin}});
  safeFailure(result, 'runtime_missing'); assert(!result.stdout.includes(fixture.root));
});

test('old and malformed runtime versions are refused without evaluating entry code', async t => {
  for (const version of ['v21.99.0', 'v20.0.0', 'v18.20.0', 'malformed-version-private-diagnostic']) {
    await t.test(version, async sub => {
      const fixture = await bundleFixture(sub);
      const marker = join(fixture.root, 'entry-executed');
      const bin = await fakeRuntime(fixture, `if [ "$1" = '--version' ]; then printf '%s\\n' '${version}'; exit 0; fi\nprintf 'unsafe' > '${marker}'\nexit 99`);
      const result = await fixture.invoke(['--help'], {env: {PATH: bin}});
      safeFailure(result, 'runtime_unsupported');
      assert(!result.stdout.includes(version));
      await assert.rejects(readFile(marker), {code: 'ENOENT'});
    });
  }
});

test('minimum major-version probe simulation is separate from actual installed Node execution', async t => {
  const fixture = await bundleFixture(t);
  const bin = await fakeRuntime(fixture,
    `if [ "$1" = '--version' ] || [ "$1" = '-e' ]; then [ -z "\${VORTICE_LOCAL_AGENT_TOKEN:-}" ] || exit 91; fi\nif [ "$1" = '--version' ]; then printf 'v22.0.0\\n'; exit 0; fi\nexec '${process.execPath}' "$@"`);
  const result = await fixture.invoke(['--help'], {env: {PATH: bin}});
  assert.equal(result.status, 0); assert.equal(result.stderr, '');
  const help = JSON.parse(result.stdout);
  assert.equal(help.ok, true);
  // Only the version string is simulated. Both the token-empty inline preflight
  // and module execution use this installed Node, without a Node-22 run claim.
  assert.equal(help.runtime_version, process.versions.node);
});

test('Node module and instrumentation overrides are scrubbed before runtime probe', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  const marker = join(fixture.root, 'preload-ran'), preload = join(fixture.root, 'unsafe-preload.cjs');
  await writeFile(preload, `require('node:fs').writeFileSync(${JSON.stringify(marker)}, 'instrumented');throw new Error('private instrumentation diagnostic');`);
  const bin = await fakeRuntime(fixture,
    `if [ "\${NODE_OPTIONS+x}" = x ] || [ "\${NODE_PATH+x}" = x ]; then printf 'override escaped scrub' >&2; exit 90; fi\nexec '${process.execPath}' "$@"`);
  const result = await fixture.invoke(['work', 'list', ...explicit(server.socketPath)],
    {env: {PATH: bin, NODE_OPTIONS: `--require=${preload}`, NODE_PATH: fixture.root}});
  assert.equal(result.status, 0); assert.equal(result.stderr, '');
  await assert.rejects(readFile(marker), {code: 'ENOENT'});
  assert.deepEqual(server.received.map(r => r.command), ['capabilities', 'work.list']);
});

test('runtime version and inline preflight receive no token while the client retains the synthetic token', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  const bin = await fakeRuntime(fixture,
    `if [ "$1" = '--version' ] || [ "$1" = '-e' ]; then [ -z "\${VORTICE_LOCAL_AGENT_TOKEN:-}" ] || exit 91; fi\nexec '${process.execPath}' "$@"`);
  const result = await fixture.invoke(['work', 'list', ...explicit(server.socketPath)], {env: {PATH: bin}});
  assert.equal(result.status, 0); assert.equal(result.stderr, '');
  assert(server.received.every(r => r.credential.token === token));
});

test('connection files reject mixed, duplicated and malformed inputs before any dispatch', async t => {
  const mutations = [
    ['extra field', value => ({...value, token: token})],
    ['protocol', value => ({...value, protocol_version: 2})],
    ['scope field', value => ({...value, scope: {...value.scope, extra: 'untrusted'}})],
    ['scope value', value => ({...value, scope: {...value.scope, company_id: '../../outside'}})],
    ['token environment', value => ({...value, token_environment: 'ANOTHER_TOKEN'})],
    ['socket path', value => ({...value, socket_path: 'relative.sock'})],
    ['socket bytes', value => ({...value, socket_path: `/${'空'.repeat(34)}`})],
    ['array', () => []], ['null', () => null],
  ];
  for (const [name, mutation] of mutations) await t.test(name, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const settings = await connectionFile(fixture, server.socketPath);
    await writeFile(settings.file, JSON.stringify(mutation(settings.settings)));
    safeFailure(await fixture.invoke(['work', 'list', '--connection', settings.file]), 'connection_invalid');
    assert.equal(server.received.length, 0);
  });
  for (const suffix of [['--workspace', 'other'], ['--socket', '/other.sock'],
    ['--company', 'other'], ['--device', 'other'], ['--connection', 'another.json']]) {
    await t.test(suffix[0], async sub => {
      const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
      const settings = await connectionFile(fixture, server.socketPath);
      safeFailure(await fixture.invoke(['work', 'list', '--connection', settings.file, ...suffix]), 'connection_invalid');
      assert.equal(server.received.length, 0);
    });
  }
});

test('connection malformed UTF-8, JSON and oversized bytes are safely refused', async t => {
  for (const [name, data] of [['JSON', '{private-invalid'], ['UTF-8', Buffer.from([0xff, 0xfe])],
    ['oversize', ' '.repeat(16385)]]) await t.test(name, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const settings = await connectionFile(fixture, server.socketPath);
    await writeFile(settings.file, data);
    const result = await fixture.invoke(['work', 'list', '--connection', settings.file]);
    safeFailure(result, 'connection_invalid'); assert(!result.stdout.includes('private-invalid'));
    assert.equal(server.received.length, 0);
  });
});

test('connection 16 KiB bound accepts the exact bound and rejects one byte beyond', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  const settings = await connectionFile(fixture, server.socketPath);
  const json = JSON.stringify(settings.settings), exact = json + ' '.repeat(16384 - Buffer.byteLength(json));
  await writeFile(settings.file, exact);
  assert.equal((await fixture.invoke(['work', 'list', '--connection', settings.file])).status, 0);
  const requests = server.received.length;
  await writeFile(settings.file, `${exact} `);
  safeFailure(await fixture.invoke(['work', 'list', '--connection', settings.file]), 'connection_invalid');
  assert.equal(server.received.length, requests);
});

test('connection unsafe modes, symbolic links and hard links are retained untouched', async t => {
  for (const kind of ['file mode', 'parent mode', 'file symlink', 'parent symlink', 'hardlink']) {
    await t.test(kind, async sub => {
      const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
      const settings = await connectionFile(fixture, server.socketPath);
      let file = settings.file;
      const original = await readFile(file);
      if (kind === 'file mode') await chmod(file, 0o644);
      if (kind === 'parent mode') await chmod(settings.parent, 0o755);
      if (kind === 'file symlink') {
        const moved = `${file}.original`; await rename(file, moved); await symlink(moved, file);
      }
      if (kind === 'parent symlink') {
        const alias = join(fixture.root, 'settings alias'); await symlink(settings.parent, alias);
        file = join(alias, 'office connection 空间.json');
      }
      if (kind === 'hardlink') await link(file, `${file}.linked`);
      safeFailure(await fixture.invoke(['work', 'list', '--connection', file]), 'connection_unsafe');
      assert.deepEqual(await readFile(file), original); assert.equal(server.received.length, 0);
    });
  }
});

test('missing or changed packaged runtime files cannot reach the endpoint', async t => {
  for (const relative of ['agent-cli/client.mjs', 'agent-cli/contract.mjs',
    'agent-cli/transport.mjs', 'AGENT-CLI.md']) await t.test(relative, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const path = join(fixture.bundle, relative);
    const original = await readFile(path);
    await writeFile(path, Buffer.concat([original, Buffer.from('\n// changed distribution bytes\n')]));
    safeFailure(await fixture.invoke(['work', 'list', ...explicit(server.socketPath)]), 'bundle_invalid');
    assert.equal(server.received.length, 0);
  });
});

test('missing modules and corrupt executable JavaScript refuse before module evaluation', async t => {
  for (const relative of ['agent-cli/cli.mjs', 'agent-cli/client.mjs', 'agent-cli/contract.mjs',
    'agent-cli/transport.mjs', 'agent-cli/distribution/entry.mjs', 'AGENT-CLI.md']) {
    await t.test(`missing ${relative}`, async sub => {
      const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
      await unlink(join(fixture.bundle, relative));
      safeFailure(await fixture.invoke(['work', 'list', ...explicit(server.socketPath)]), 'bundle_invalid');
      assert.equal(server.received.length, 0);
    });
  }
  await t.test('changed client executable', async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const file = join(fixture.bundle, 'agent-cli/client.mjs');
    await writeFile(file, `throw new Error('private corrupt module diagnostic');\n${await readFile(file, 'utf8')}`);
    const result = await fixture.invoke(['work', 'list', ...explicit(server.socketPath)]);
    safeFailure(result, 'bundle_invalid'); assert(!result.stdout.includes('private corrupt module'));
    assert.equal(server.received.length, 0);
  });
});

test('connection JSON duplicate and escaped duplicate keys cannot choose an endpoint', async t => {
  for (const escaped of [false, true]) await t.test(escaped ? 'escaped' : 'literal', async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const settings = await connectionFile(fixture, server.socketPath);
    const extra = escaped ? '"protocol_\\u0076ersion":1' : '"protocol_version":1';
    await writeFile(settings.file, JSON.stringify(settings.settings).replace('{', `{${extra},`));
    safeFailure(await fixture.invoke(['work', 'list', '--connection', settings.file]), 'connection_invalid');
    assert.equal(server.received.length, 0);
  });
});

test('stale settings and unsafe endpoints cannot discover or fall back to another socket', async t => {
  for (const kind of ['absent', 'socket mode', 'parent mode', 'socket symlink']) await t.test(kind, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    let socketPath = server.socketPath;
    if (kind === 'absent') socketPath = `${server.socketPath}.old`;
    if (kind === 'socket mode') await chmod(socketPath, 0o644);
    if (kind === 'parent mode') await chmod(join(fixture.root, 'unix'), 0o755);
    if (kind === 'socket symlink') {
      socketPath = join(fixture.root, 'unix', 'alias.sock'); await symlink(server.socketPath, socketPath);
    }
    const settings = await connectionFile(fixture, socketPath);
    safeFailure(await fixture.invoke(['work', 'list', '--connection', settings.file]), 'service_unavailable', 'not_sent', 1);
    assert.equal(server.received.length, 0);
  });
});

test('inventory rejects missing, malformed and extra path metadata', async t => {
  for (const [name, mutate] of [
    ['protocol', m => {m.protocol_version = 2;}],
    ['client version', m => {m.client_version = '999.0.0';}],
    ['source sha', m => {m.client_source_revision = 'not-a-revision';}],
    ['archive sha', m => {m.application_archive_sha256 = token;}],
    ['missing file', m => {delete m.files['agent-cli/client.mjs'];}],
    ['extra file', m => {m.files['../private'] = {...m.files['AGENT-CLI.md']};}],
    ['size', m => {m.files['AGENT-CLI.md'].bytes++;}],
    ['hash', m => {m.files['AGENT-CLI.md'].sha256 = '0'.repeat(64);}],
    ['special mode', m => {m.files['AGENT-CLI.md'].mode = 0o1644;}],
    ['extra metadata', m => {m.private = token;}],
  ]) await t.test(name, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    mutate(fixture.metadata); await fixture.saveMetadata();
    safeFailure(await fixture.invoke(['work', 'list', ...explicit(server.socketPath)]), 'bundle_invalid');
    assert.equal(server.received.length, 0);
  });
});

test('missing and duplicate-key bundle manifests refuse before loading client modules', async t => {
  for (const kind of ['missing', 'malformed', 'duplicate']) await t.test(kind, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const file = join(fixture.bundle, 'agent-cli/distribution/bundle.json');
    if (kind === 'missing') await unlink(file);
    if (kind === 'malformed') await writeFile(file, '{private malformed metadata');
    if (kind === 'duplicate') {
      await writeFile(file, JSON.stringify(fixture.metadata).replace('{', '{"protocol_version":1,'));
    }
    safeFailure(await fixture.invoke(['work', 'list', ...explicit(server.socketPath)]), 'bundle_invalid');
    assert.equal(server.received.length, 0);
  });
});

test('bundle links and group-writable modules refuse without repairing bytes or modes', async t => {
  for (const kind of ['symlink', 'hardlink', 'writable']) await t.test(kind, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root);
    const path = join(fixture.bundle, 'agent-cli/client.mjs'), bytes = await readFile(path);
    if (kind === 'symlink') {
      const target = `${path}.original`; await rename(path, target); await symlink(target, path);
    }
    if (kind === 'hardlink') await link(path, `${path}.other`);
    if (kind === 'writable') await chmod(path, 0o664);
    safeFailure(await fixture.invoke(['work', 'list', ...explicit(server.socketPath)]), 'bundle_invalid');
    assert.deepEqual(await readFile(path), bytes); assert.equal(server.received.length, 0);
  });
});

test('restrictive extracted text modes remain usable without chmod repair', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  for (const relative of Object.keys(fixture.metadata.files)) {
    if (relative !== 'bin/vortice-agent') await chmod(join(fixture.bundle, relative), 0o600);
  }
  await chmod(join(fixture.bundle, 'agent-cli/distribution/bundle.json'), 0o600);
  assert.equal((await fixture.invoke(['work', 'list', ...explicit(server.socketPath)])).status, 0);
  for (const relative of Object.keys(fixture.metadata.files)) {
    if (relative !== 'bin/vortice-agent') assert.equal((await lstat(join(fixture.bundle, relative))).mode & 0o7777, 0o600);
  }
});

test('capability mismatch blocks the requested command and preserves proposal operation', async t => {
  const scenarios = [
    ['version', r => ({...standardReply(r), protocol_version: 2}), 'invalid_response'],
    ['scope', r => ({...standardReply(r), scope: {...scope, company_id: 'other'}}), 'invalid_response'],
    ['missing command', r => response(r, {commands: ['capabilities'], proposal_types: ['inspection.notes']}), 'unsupported_command'],
    ['missing type', r => response(r, {commands: [...commands], proposal_types: []}), 'unsupported_proposal'],
    ['malformed commands', r => response(r, {commands: 'proposals.create', proposal_types: ['inspection.notes']}), 'invalid_response'],
    ['denied', r => ({protocol_version: 1, request_id: r.request_id, scope: r.scope, ok: false,
      error: {code: 'grant_revoked', retryable: false, outcome: 'rejected'}}), 'grant_revoked'],
  ];
  for (const [name, reply, code] of scenarios) await t.test(name, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root,
      (socket, request) => socket.end(`${JSON.stringify(reply(request))}\n`));
    const input = JSON.stringify({type: 'inspection.notes', job_id: 'job_a', expected_document_hash: 'a'.repeat(64), notes: 'Kept operation'});
    const result = await fixture.invoke(['proposals', 'create', ...explicit(server.socketPath), '--operation', operation, '--input', '-'], {input});
    const error = safeFailure(result, code, 'not_sent', 1);
    assert.equal(error.error.idempotency_key, operation);
    assert.deepEqual(server.received.map(r => r.command), ['capabilities']);
  });
});

test('capability framing and UTF-8 errors never dispatch the requested command', async t => {
  for (const [name, bytes] of [
    ['malformed JSON', () => '{private diagnostic\n'],
    ['invalid UTF-8', () => Buffer.from([0xff, 10])],
    ['extra frame', r => `${JSON.stringify(standardReply(r))}\n{}\n`],
    ['oversized', () => `${'x'.repeat(1024 * 1024 + 1)}\n`],
  ]) await t.test(name, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root,
      (socket, request) => socket.end(bytes(request)));
    safeFailure(await fixture.invoke(['work', 'list', ...explicit(server.socketPath)]), 'invalid_response', 'not_sent', 1);
    assert.deepEqual(server.received.map(r => r.command), ['capabilities']);
  });
});

test('post-preflight service rejection and lost reply preserve v1 outcomes without write retry', async t => {
  for (const kind of ['rejected', 'unknown']) await t.test(kind, async sub => {
    const fixture = await bundleFixture(sub), server = await protocolFixture(sub, fixture.root,
      (socket, request) => {
        if (request.command === 'capabilities') socket.end(`${JSON.stringify(standardReply(request))}\n`);
        else if (kind === 'unknown') socket.destroy();
        else socket.end(`${JSON.stringify({protocol_version: 1, request_id: request.request_id,
          scope: request.scope, ok: false, error: {code: 'permission_denied', retryable: false, outcome: 'rejected'}})}\n`);
      });
    const input = JSON.stringify({type: 'inspection.notes', job_id: 'job_a', expected_document_hash: 'a'.repeat(64), notes: 'No auto retry'});
    const result = await fixture.invoke(['proposals', 'create', ...explicit(server.socketPath), '--operation', operation, '--input', '-'], {input});
    safeFailure(result, kind === 'unknown' ? 'service_unavailable' : 'permission_denied', kind, kind === 'unknown' ? 3 : 1);
    assert.deepEqual(server.received.map(r => r.command), ['capabilities', 'proposals.create']);
  });
});

test('quoted Unicode notes and operation pass once without shell expansion', async t => {
  const fixture = await bundleFixture(t), server = await protocolFixture(t, fixture.root);
  const notes = 'Engine 空间 café $HOME `whoami` $(touch NO) "quoted"\nsecond line';
  const input = JSON.stringify({type: 'inspection.notes', job_id: 'job_a', expected_document_hash: 'a'.repeat(64), notes});
  const result = await fixture.invoke(['proposals', 'create', ...explicit(server.socketPath), '--operation', operation, '--input', '-'], {input});
  assert.equal(result.status, 0); assert.equal(result.stderr, '');
  assert.equal(JSON.parse(result.stdout).result.item.notes, notes);
  assert.equal(server.received[1].args.notes, notes);
  assert.equal(server.received[1].args.idempotency_key, operation);
  assert.deepEqual(server.received.map(r => r.command), ['capabilities', 'proposals.create']);
});
