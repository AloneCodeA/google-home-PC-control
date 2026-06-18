/**
 * Minimal host-client contract owned by the restart supervisor.
 */
export interface ManagedScreenHostClient {
  /** Requests a display power state. */
  setDisplayPower(isOn: boolean): Promise<void>;

  /** Subscribes to actual Windows display state changes. */
  onDisplayStateChanged(listener: (isOn: boolean) => void): () => void;

  /** Stops the host client. */
  dispose(): Promise<void>;
}

/**
 * Owns the active screen host and retries a failed command with one fresh host.
 */
export class ScreenHostSupervisor implements ManagedScreenHostClient {
  private client: ManagedScreenHostClient;
  private unsubscribeClientState: () => void;
  private readonly stateListeners = new Set<(isOn: boolean) => void>();
  private commandTail: Promise<void> = Promise.resolve();

  /**
   * Creates a supervisor and immediately starts its first host client.
   *
   * @param clientFactory Creates an independent host client.
   */
  constructor(private readonly clientFactory: () => ManagedScreenHostClient) {
    this.client = this.clientFactory();
    this.unsubscribeClientState = this.bindClientState(this.client);
  }

  /** {@inheritDoc ManagedScreenHostClient.setDisplayPower} */
  setDisplayPower(isOn: boolean): Promise<void> {
    const command = this.commandTail.then(() =>
      this.executeWithOneRetry(isOn),
    );
    this.commandTail = command.catch(() => {});
    return command;
  }

  private async executeWithOneRetry(isOn: boolean): Promise<void> {
    try {
      await this.client.setDisplayPower(isOn);
      return;
    } catch {
      this.unsubscribeClientState();
      await this.client.dispose();
      this.client = this.clientFactory();
      this.unsubscribeClientState = this.bindClientState(this.client);
    }

    await this.client.setDisplayPower(isOn);
  }

  /** {@inheritDoc ManagedScreenHostClient.onDisplayStateChanged} */
  onDisplayStateChanged(listener: (isOn: boolean) => void): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  /** {@inheritDoc ManagedScreenHostClient.dispose} */
  async dispose(): Promise<void> {
    this.unsubscribeClientState();
    this.stateListeners.clear();
    await this.client.dispose();
  }

  private bindClientState(client: ManagedScreenHostClient): () => void {
    return client.onDisplayStateChanged((isOn) => {
      for (const listener of this.stateListeners) {
        listener(isOn);
      }
    });
  }
}
