#!/usr/bin/env node
import {pathToFileURL} from 'node:url';
import {CliError, COMMANDS, safeError, validateScope, PROTOCOL_VERSION} from './contract.mjs';
import {execute} from './client.mjs';
import {socketTransport} from './transport.mjs';

export const help = {
  protocol_version: PROTOCOL_VERSION, client: 'vortice-local-agent', version: '0.1.0',
  status: 'service_integration_pending', commands: Object.keys(COMMANDS),
  required_options: ['--socket', '--workspace', '--company', '--device'],
  authentication: 'VORTICE_LOCAL_AGENT_TOKEN environment; never a command argument',
  show_options: ['--id'], list_options: ['--limit (1..100)', '--cursor', '--job', '--equipment'],
  proposal_options: ['--operation UUID', '--input - (JSON on stdin)'],
  proposal_schema: {type: 'inspection.notes', job_id: 'id', expected_document_hash: '64 lowercase hex', notes: 'suggested replacement text'},
  unavailable: ['manual pages', 'recurring plans', 'inventory', 'billing', 'approval', 'publication', 'permission changes', 'proposal apply'],
};
export function parseArgs(argv, input = '', preflight = false) {
  const words = [], opts = new Map();
  for (let n = 0; n < argv.length; n++) {
    const word = argv[n];
    if (!word.startsWith('--')) {
      if (opts.size) throw new CliError('invalid_input');
      words.push(word); continue;
    }
    const value = argv[++n];
    if (!value || value.startsWith('--') || opts.has(word)) throw new CliError('invalid_input');
    opts.set(word, value);
  }
  const command = words.join('.');
  if (!Object.hasOwn(COMMANDS, command)) throw new CliError('invalid_input');
  const def = COMMANDS[command];
  const allowed = new Set(['--socket', '--workspace', '--company', '--device']);
  if (def.args === 'id') allowed.add('--id');
  if (def.args === 'list') for (const key of ['--limit', '--cursor', '--job', '--equipment']) allowed.add(key);
  if (def.args === 'proposal') { allowed.add('--operation'); allowed.add('--input'); }
  if ([...opts.keys()].some(k => !allowed.has(k))) throw new CliError('invalid_input');
  const scope = {workspace_id: opts.get('--workspace'), company_id: opts.get('--company'), device_id: opts.get('--device')};
  validateScope(scope);
  const socketPath = opts.get('--socket');
  if (!socketPath?.startsWith('/') || socketPath.includes('\0') || socketPath.length > 100) throw new CliError('invalid_input');
  let args = {};
  if (def.args === 'id') args[def.idKey] = opts.get('--id');
  if (def.args === 'list') {
    args.limit = opts.has('--limit') ? (/^[0-9]+$/.test(opts.get('--limit')) ? Number(opts.get('--limit')) : NaN) : 25;
    for (const [flag, key] of [['--cursor', 'cursor'], ['--job', 'job_id'], ['--equipment', 'equipment_id']]) {
      if (opts.has(flag)) args[key] = opts.get(flag);
    }
  }
  if (def.args === 'proposal') {
    if (opts.get('--input') !== '-' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(opts.get('--operation') ?? '') ||
        Buffer.byteLength(input) > 64 * 1024) throw new CliError('invalid_input');
    if (preflight) return {socketPath, intent: {command, scope, args}};
    try { args = JSON.parse(input); } catch { throw new CliError('invalid_input'); }
    if (args === null || typeof args !== 'object' || Array.isArray(args) || Object.hasOwn(args, 'idempotency_key')) {
      throw new CliError('invalid_input');
    }
    args.idempotency_key = opts.get('--operation');
  } else if (input) throw new CliError('invalid_input');
  return {socketPath, intent: {command, scope, args}};
}
export async function run(argv, {env = process.env, stdin = process.stdin, transport = socketTransport} = {}) {
  if (argv.length === 0 || argv.length === 1 && ['help', '--help'].includes(argv[0])) return {...help, ok: true};
  try {
    // Reject malformed command/options/scope before waiting for proposal stdin.
    parseArgs(argv, '', true);
    let input = '';
    if (argv.includes('--input')) {
      if (argv[argv.indexOf('--input') + 1] !== '-') throw new CliError('invalid_input');
      let bytes = 0;
      const chunks = [];
      for await (const chunk of stdin) {
        bytes += Buffer.byteLength(chunk);
        if (bytes > 64 * 1024) throw new CliError('invalid_input');
        chunks.push(Buffer.from(chunk));
      }
      try { input = new TextDecoder('utf-8', {fatal: true}).decode(Buffer.concat(chunks)); }
      catch { throw new CliError('invalid_input'); }
    }
    const parsed = parseArgs(argv, input);
    return await execute(parsed.intent, {transport, token: env.VORTICE_LOCAL_AGENT_TOKEN, socketPath: parsed.socketPath});
  } catch (e) { return safeError(e); }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const result = await run(process.argv.slice(2));
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exitCode = result.ok ? 0 : result.error.outcome === 'unknown' ? 3 : result.error.code === 'invalid_input' ? 2 : 1;
}
