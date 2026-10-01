import { randomUUID } from 'node:crypto';
import { CliError, PROTOCOL_VERSION, safeError, validateIntent, validateResponse } from './contract.mjs';

export async function execute(intent, {transport, token, socketPath, request_id = randomUUID()} = {}) {
  let request;
  try {
    validateIntent(intent);
    if (typeof token !== 'string' || token.length < 16 || token.length > 4096 || /[\s\x00-\x1f\x7f]/.test(token)) {
      throw new CliError('auth_required');
    }
    if (typeof socketPath !== 'string' || !socketPath.startsWith('/') || socketPath.includes('\0') || socketPath.length > 100) {
      throw new CliError('invalid_input');
    }
    request = {protocol_version: PROTOCOL_VERSION, request_id, scope: {...intent.scope},
      command: intent.command, args: structuredClone(intent.args)};
    // Authorization is deliberately delegated to the shared service. There is
    // no DB open, phone-bundle fallback or locally manufactured capability.
    const reply = await transport({request, token, socketPath});
    return validateResponse(reply, request);
  } catch (error) {
    return safeError(error, request?.request_id ?? null, request?.args.idempotency_key);
  }
}
