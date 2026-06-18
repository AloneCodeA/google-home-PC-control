import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { createInterface, type Interface as ReadLineInterface } from 'node:readline';

import type { ScreenHostTransport } from './screen-host-transport.js';

/**
 * Connects the Matterbridge plugin to the Windows host through redirected stdio.
 */
export class ChildProcessScreenHostTransport implements ScreenHostTransport {
  private readonly childProcess: ChildProcessWithoutNullStreams;
  private readonly readLine: ReadLineInterface;
  private readonly lineListeners = new Set<(line: string) => void>();
  private readonly exitListeners = new Set<(error: Error) => void>();
  private stderr = '';
  private disposing = false;

  /**
   * Starts the screen-control host with hidden windows and piped standard streams.
   *
   * @param executablePath Absolute path to the host executable.
   * @param args Optional executable arguments.
   */
  constructor(executablePath: string, args: readonly string[] = []) {
    this.childProcess = spawn(executablePath, [...args], {
      stdio: 'pipe',
      windowsHide: true,
    });
    this.readLine = createInterface({ input: this.childProcess.stdout });
    this.readLine.on('line', (line) => {
      for (const listener of this.lineListeners) {
        listener(line);
      }
    });
    this.childProcess.stderr.setEncoding('utf8');
    this.childProcess.stderr.on('data', (chunk: string) => {
      this.stderr = `${this.stderr}${chunk}`.slice(-4096);
    });
    this.childProcess.on('error', (error) => this.publishExit(error));
    this.childProcess.on('exit', (code, signal) => {
      if (!this.disposing) {
        const detail = this.stderr.trim();
        this.publishExit(
          new Error(
            `Screen control host exited unexpectedly (code=${code ?? 'null'}, signal=${signal ?? 'none'}).${detail.length > 0 ? ` ${detail}` : ''}`,
          ),
        );
      }
    });
  }

  /** {@inheritDoc ScreenHostTransport.writeLine} */
  writeLine(line: string): void {
    if (!this.childProcess.stdin.writable) {
      throw new Error('Screen control host stdin is not writable.');
    }
    this.childProcess.stdin.write(`${line}\n`, 'utf8');
  }

  /** {@inheritDoc ScreenHostTransport.onLine} */
  onLine(listener: (line: string) => void): () => void {
    this.lineListeners.add(listener);
    return () => this.lineListeners.delete(listener);
  }

  /** {@inheritDoc ScreenHostTransport.onExit} */
  onExit(listener: (error: Error) => void): () => void {
    this.exitListeners.add(listener);
    return () => this.exitListeners.delete(listener);
  }

  /** {@inheritDoc ScreenHostTransport.dispose} */
  async dispose(): Promise<void> {
    if (this.disposing) {
      return;
    }

    this.disposing = true;
    this.lineListeners.clear();
    this.exitListeners.clear();
    this.readLine.close();

    if (this.childProcess.exitCode !== null || this.childProcess.signalCode !== null) {
      return;
    }

    const exited = new Promise<void>((resolve) => {
      this.childProcess.once('exit', () => resolve());
    });
    this.childProcess.stdin.end();

    const forceKill = setTimeout(() => {
      if (this.childProcess.exitCode === null && this.childProcess.signalCode === null) {
        this.childProcess.kill();
      }
    }, 2000);
    forceKill.unref();

    await exited;
    clearTimeout(forceKill);
  }

  private publishExit(error: Error): void {
    for (const listener of this.exitListeners) {
      listener(error);
    }
  }
}
