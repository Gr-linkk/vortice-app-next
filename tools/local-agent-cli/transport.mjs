import net from 'node:net';
import {lstat, realpath} from 'node:fs/promises';
import {dirname} from 'node:path';
import {CliError, MAX_BYTES} from './contract.mjs';

/** One request/response per Unix stream. Never discover/open a database. */
export async function socketTransport({request, token, socketPath, timeoutMs = 5000}) {
  // Check the private local endpoint before transmitting a capability. The
  // service still authenticates the grant; filesystem ownership grants no data.
  try {
    const parentPath = dirname(socketPath);
    const [parent, endpoint, resolved] = await Promise.all([lstat(parentPath), lstat(socketPath), realpath(parentPath)]);
    if (!parent.isDirectory() || parent.isSymbolicLink() || resolved !== parentPath ||
        !endpoint.isSocket() || endpoint.isSymbolicLink() ||
        parent.uid !== process.getuid() || endpoint.uid !== process.getuid() ||
        (parent.mode & 0o777) !== 0o700 || (endpoint.mode & 0o777) !== 0o600) {
      throw new Error('endpoint');
    }
  } catch { throw new CliError('service_unavailable', {retryable: true, outcome: 'not_sent'}); }
  return new Promise((resolve, reject) => {
    let settled = false, bytes = 0;
    const chunks = [];
    const socket = net.createConnection({path: socketPath});
    const finish = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.destroy();
      if (error) reject(error); else resolve(result);
    };
    const fail = code => finish(new CliError(code, {retryable: true, outcome: 'unknown'}));
    const timer = setTimeout(() => fail('service_unavailable'), timeoutMs);
    socket.on('error', () => fail('service_unavailable'));
    socket.on('end', () => fail('service_unavailable'));
    socket.on('connect', () => {
      const line = JSON.stringify({...request, credential: {token}});
      if (Buffer.byteLength(line) > 64 * 1024) { fail('invalid_input'); return; }
      socket.write(`${line}\n`);
    });
    socket.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > MAX_BYTES) { fail('invalid_response'); return; }
      chunks.push(chunk);
      const accumulated = Buffer.concat(chunks);
      const newline = accumulated.indexOf(10);
      if (newline < 0) return;
      // Multiple/extra bytes cannot silently become another command's response.
      if (accumulated.subarray(newline + 1).length !== 0) { fail('invalid_response'); return; }
      try { finish(null, JSON.parse(new TextDecoder('utf-8', {fatal: true}).decode(accumulated.subarray(0, newline)))); }
      catch { fail('invalid_response'); }
    });
  });
}
