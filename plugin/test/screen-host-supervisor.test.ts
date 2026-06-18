import { describe, expect, it, vi } from 'vitest';

import {
  ScreenHostSupervisor,
  type ManagedScreenHostClient,
} from '../src/screen-host-supervisor.js';

describe('ScreenHostSupervisor', () => {
  it('recreates the host and retries a failed command exactly once', async () => {
    const first = new RecordingClient(new Error('First host failed.'));
    const second = new RecordingClient();
    const factory = vi
      .fn<() => ManagedScreenHostClient>()
      .mockReturnValueOnce(first)
      .mockReturnValueOnce(second);
    const supervisor = new ScreenHostSupervisor(factory);

    await supervisor.setDisplayPower(true);

    expect(factory).toHaveBeenCalledTimes(2);
    expect(first.requestedStates).toEqual([true]);
    expect(first.disposeCount).toBe(1);
    expect(second.requestedStates).toEqual([true]);
  });

  it('propagates the second failure without another restart', async () => {
    const first = new RecordingClient(new Error('First host failed.'));
    const second = new RecordingClient(new Error('Second host failed.'));
    const factory = vi
      .fn<() => ManagedScreenHostClient>()
      .mockReturnValueOnce(first)
      .mockReturnValueOnce(second);
    const supervisor = new ScreenHostSupervisor(factory);

    await expect(supervisor.setDisplayPower(false)).rejects.toThrow(
      'Second host failed.',
    );

    expect(factory).toHaveBeenCalledTimes(2);
  });

  it('preserves display-state subscriptions when the host is recreated', async () => {
    const first = new RecordingClient(new Error('First host failed.'));
    const second = new RecordingClient();
    const factory = vi
      .fn<() => ManagedScreenHostClient>()
      .mockReturnValueOnce(first)
      .mockReturnValueOnce(second);
    const supervisor = new ScreenHostSupervisor(factory);
    const observedStates: boolean[] = [];
    supervisor.onDisplayStateChanged((isOn) => observedStates.push(isOn));

    await supervisor.setDisplayPower(true);
    second.emitState(true);

    expect(observedStates).toEqual([true]);
  });

  it('serializes concurrent display commands in arrival order', async () => {
    const client = new ControllableClient();
    const supervisor = new ScreenHostSupervisor(() => client);

    const first = supervisor.setDisplayPower(false);
    const second = supervisor.setDisplayPower(true);
    await vi.waitFor(() => expect(client.requestedStates).toEqual([false]));

    client.completeNext();
    await first;
    await vi.waitFor(() => expect(client.requestedStates).toEqual([false, true]));

    client.completeNext();
    await second;
  });
});

class RecordingClient implements ManagedScreenHostClient {
  readonly requestedStates: boolean[] = [];
  disposeCount = 0;
  private readonly stateListeners = new Set<(isOn: boolean) => void>();

  constructor(private readonly error?: Error) {}

  async setDisplayPower(isOn: boolean): Promise<void> {
    this.requestedStates.push(isOn);
    if (this.error !== undefined) {
      throw this.error;
    }
  }

  onDisplayStateChanged(listener: (isOn: boolean) => void): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  async dispose(): Promise<void> {
    this.disposeCount++;
  }

  emitState(isOn: boolean): void {
    for (const listener of this.stateListeners) {
      listener(isOn);
    }
  }
}

class ControllableClient implements ManagedScreenHostClient {
  readonly requestedStates: boolean[] = [];
  private readonly completions: Array<() => void> = [];

  setDisplayPower(isOn: boolean): Promise<void> {
    this.requestedStates.push(isOn);
    return new Promise<void>((resolve) => this.completions.push(resolve));
  }

  onDisplayStateChanged(): () => void {
    return () => {};
  }

  async dispose(): Promise<void> {}

  completeNext(): void {
    const completion = this.completions.shift();
    if (completion === undefined) {
      throw new Error('No pending command to complete.');
    }
    completion();
  }
}
