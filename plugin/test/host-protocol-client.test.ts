import { describe, expect, it, vi } from 'vitest';

import { HostProtocolClient } from '../src/host-protocol-client.js';
import type { ScreenHostTransport } from '../src/screen-host-transport.js';

describe('HostProtocolClient', () => {
  it('correlates a successful display command by requestId', async () => {
    const transport = new RecordingTransport();
    const client = new HostProtocolClient(transport, () => 'request-1');

    const command = client.setDisplayPower(true);
    expect(transport.writtenLines).toEqual([
      '{"type":"setDisplayPower","requestId":"request-1","isOn":true}',
    ]);

    transport.emitLine(
      '{"type":"result","requestId":"request-1","success":true,"error":null}',
    );

    await expect(command).resolves.toBeUndefined();
  });

  it('rejects a failed display command with the host error', async () => {
    const transport = new RecordingTransport();
    const client = new HostProtocolClient(transport, () => 'request-2');

    const command = client.setDisplayPower(false);
    transport.emitLine(
      '{"type":"result","requestId":"request-2","success":false,"error":"Display command failed."}',
    );

    await expect(command).rejects.toThrow('Display command failed.');
  });

  it('publishes displayState events independently of command results', () => {
    const transport = new RecordingTransport();
    const client = new HostProtocolClient(transport, () => 'unused');
    const observedStates: boolean[] = [];
    client.onDisplayStateChanged((isOn) => observedStates.push(isOn));

    transport.emitLine('{"type":"displayState","isOn":false}');
    transport.emitLine('{"type":"displayState","isOn":true}');

    expect(observedStates).toEqual([false, true]);
  });

  it('rejects every pending command when the host transport exits', async () => {
    const transport = new RecordingTransport();
    const client = new HostProtocolClient(transport, () => 'request-3');

    const command = client.setDisplayPower(true);
    transport.emitExit(new Error('Host process exited.'));

    await expect(command).rejects.toThrow('Host process exited.');
  });

  it('reports malformed host output without throwing from the transport callback', () => {
    const transport = new RecordingTransport();
    const protocolErrors: Error[] = [];
    new HostProtocolClient(transport, () => 'unused', (error) =>
      protocolErrors.push(error),
    );

    expect(() => transport.emitLine('{')).not.toThrow();

    expect(protocolErrors).toHaveLength(1);
    expect(protocolErrors[0]?.message).toContain('Invalid JSON from screen control host');
  });

  it('rejects and removes a command that exceeds its response timeout', async () => {
    vi.useFakeTimers();
    try {
      const transport = new RecordingTransport();
      const client = new HostProtocolClient(
        transport,
        () => 'request-timeout',
        () => {},
        1000,
      );
      let rejection: Error | undefined;
      void client.setDisplayPower(true).catch((error: unknown) => {
        rejection = error instanceof Error ? error : new Error(String(error));
      });

      await vi.advanceTimersByTimeAsync(1000);

      expect(rejection?.message).toBe(
        "Timed out waiting for screen control host request 'request-timeout'.",
      );
    } finally {
      vi.useRealTimers();
    }
  });

  it('dispose rejects pending commands and releases the transport', async () => {
    const transport = new RecordingTransport();
    const client = new HostProtocolClient(transport, () => 'request-dispose');
    const command = client.setDisplayPower(true);

    await client.dispose();

    await expect(command).rejects.toThrow('Screen control protocol client disposed.');
    expect(transport.disposeCount).toBe(1);
  });
});

class RecordingTransport implements ScreenHostTransport {
  readonly writtenLines: string[] = [];
  disposeCount = 0;
  private lineListener: ((line: string) => void) | undefined;
  private exitListener: ((error: Error) => void) | undefined;

  writeLine(line: string): void {
    this.writtenLines.push(line);
  }

  onLine(listener: (line: string) => void): () => void {
    this.lineListener = listener;
    return () => {
      this.lineListener = undefined;
    };
  }

  onExit(listener: (error: Error) => void): () => void {
    this.exitListener = listener;
    return () => {
      this.exitListener = undefined;
    };
  }

  async dispose(): Promise<void> {
    this.disposeCount++;
  }

  emitLine(line: string): void {
    this.lineListener?.(line);
  }

  emitExit(error: Error): void {
    this.exitListener?.(error);
  }
}
