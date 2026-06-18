import process from 'node:process';

import { describe, expect, it } from 'vitest';

import { ChildProcessScreenHostTransport } from '../src/child-process-screen-host-transport.js';

describe('ChildProcessScreenHostTransport', () => {
  it('writes and receives complete UTF-8 lines through a real child process', async () => {
    const transport = new ChildProcessScreenHostTransport(process.execPath, [
      '-e',
      "process.stdin.pipe(process.stdout)",
    ]);
    const receivedLine = new Promise<string>((resolve) => {
      transport.onLine(resolve);
    });

    transport.writeLine('{"hello":"world"}');

    await expect(receivedLine).resolves.toBe('{"hello":"world"}');
    await transport.dispose();
  });
});
