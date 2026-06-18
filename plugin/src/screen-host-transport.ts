/**
 * Represents the line-oriented transport connected to the Windows screen-control host.
 */
export interface ScreenHostTransport {
  /** Writes one JSON object without a trailing newline. */
  writeLine(line: string): void;

  /** Subscribes to complete lines received from the host. */
  onLine(listener: (line: string) => void): () => void;

  /** Subscribes to unexpected transport termination. */
  onExit(listener: (error: Error) => void): () => void;

  /** Stops the transport and releases process resources. */
  dispose(): Promise<void>;
}
