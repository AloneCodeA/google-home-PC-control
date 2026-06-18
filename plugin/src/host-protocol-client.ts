import type { ScreenHostTransport } from './screen-host-transport.js';

interface PendingRequest {
  resolve: () => void;
  reject: (error: Error) => void;
  timeout: ReturnType<typeof setTimeout>;
}

interface HostResult {
  type: 'result';
  requestId: string;
  success: boolean;
  error: string | null;
}

interface HostDisplayState {
  type: 'displayState';
  isOn: boolean;
}

/**
 * Correlates display commands with JSON Lines responses from the Windows host.
 */
export class HostProtocolClient {
  private readonly pendingRequests = new Map<string, PendingRequest>();
  private readonly displayStateListeners = new Set<(isOn: boolean) => void>();
  private readonly unsubscribeLine: () => void;
  private readonly unsubscribeExit: () => void;
  private disposed = false;

  /**
   * Creates a protocol client over an active host transport.
   *
   * @param transport Active line-oriented child-process transport.
   * @param requestIdFactory Generates a unique identifier for each command.
   * @param onProtocolError Receives malformed or unsupported host output.
   * @param requestTimeoutMs Maximum time to wait for a correlated result.
   */
  constructor(
    private readonly transport: ScreenHostTransport,
    private readonly requestIdFactory: () => string,
    private readonly onProtocolError: (error: Error) => void = () => {},
    private readonly requestTimeoutMs = 5000,
  ) {
    this.unsubscribeLine = this.transport.onLine((line) => this.handleLine(line));
    this.unsubscribeExit = this.transport.onExit((error) => this.handleExit(error));
  }

  /**
   * Requests a display power change and resolves after the correlated host result succeeds.
   *
   * @param isOn Whether all displays should be on.
   */
  setDisplayPower(isOn: boolean): Promise<void> {
    const requestId = this.requestIdFactory();
    const completion = new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        if (this.pendingRequests.delete(requestId)) {
          reject(
            new Error(
              `Timed out waiting for screen control host request '${requestId}'.`,
            ),
          );
        }
      }, this.requestTimeoutMs);
      this.pendingRequests.set(requestId, { resolve, reject, timeout });
    });

    this.transport.writeLine(
      JSON.stringify({ type: 'setDisplayPower', requestId, isOn }),
    );
    return completion;
  }

  /**
   * Subscribes to actual Windows display-state changes.
   *
   * @param listener Called when Windows reports a new display state.
   * @returns A function that removes the subscription.
   */
  onDisplayStateChanged(listener: (isOn: boolean) => void): () => void {
    this.displayStateListeners.add(listener);
    return () => this.displayStateListeners.delete(listener);
  }

  /** Stops protocol processing and releases the child-process transport. */
  async dispose(): Promise<void> {
    if (this.disposed) {
      return;
    }

    this.disposed = true;
    this.unsubscribeLine();
    this.unsubscribeExit();
    this.displayStateListeners.clear();
    this.handleExit(new Error('Screen control protocol client disposed.'));
    await this.transport.dispose();
  }

  private handleLine(line: string): void {
    let result: HostResult | HostDisplayState;
    try {
      result = JSON.parse(line) as HostResult | HostDisplayState;
    } catch (error) {
      this.onProtocolError(
        new Error(
          `Invalid JSON from screen control host: ${error instanceof Error ? error.message : String(error)}`,
          { cause: error },
        ),
      );
      return;
    }
    if (result.type === 'displayState') {
      for (const listener of this.displayStateListeners) {
        listener(result.isOn);
      }
      return;
    }

    if (result.type !== 'result') {
      return;
    }

    const pending = this.pendingRequests.get(result.requestId);
    if (pending === undefined) {
      return;
    }

    this.pendingRequests.delete(result.requestId);
    clearTimeout(pending.timeout);
    if (result.success) {
      pending.resolve();
    } else {
      pending.reject(
        new Error(result.error ?? 'Screen control host rejected the command.'),
      );
    }
  }

  private handleExit(error: Error): void {
    for (const pending of this.pendingRequests.values()) {
      clearTimeout(pending.timeout);
      pending.reject(error);
    }
    this.pendingRequests.clear();
  }
}
