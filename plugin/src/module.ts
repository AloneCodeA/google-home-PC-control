import { randomUUID } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  type BasePlatformConfig,
  MatterbridgeDynamicPlatform,
  MatterbridgeEndpoint,
  onOffPlugInUnit,
  type PlatformMatterbridge,
} from 'matterbridge';
import type { AnsiLogger } from 'matterbridge/logger';
import { OnOff } from 'matterbridge/matter/clusters';

import { ChildProcessScreenHostTransport } from './child-process-screen-host-transport.js';
import { HostProtocolClient } from './host-protocol-client.js';
import {
  ScreenHostSupervisor,
  type ManagedScreenHostClient,
} from './screen-host-supervisor.js';

const RequiredMatterbridgeVersion = '3.9.0';
const DeviceSerialNumber = 'ALONE-COMPUTER-SCREEN-001';

/** Configuration accepted by the Computer Screen Matterbridge platform. */
export type ScreenControlPlatformConfig = BasePlatformConfig & {
  deviceName: string;
  hostExecutable: string;
};

type SupervisorFactory = () => ManagedScreenHostClient;

/**
 * Standard Matterbridge plugin entry point.
 *
 * @param matterbridge Active Matterbridge platform API.
 * @param log Matterbridge logger.
 * @param config Persisted plugin configuration.
 * @returns The initialized Computer Screen platform.
 */
export default function initializePlugin(
  matterbridge: PlatformMatterbridge,
  log: AnsiLogger,
  config: ScreenControlPlatformConfig,
): ScreenControlPlatform {
  return new ScreenControlPlatform(matterbridge, log, config);
}

/**
 * Registers one Matter outlet representing the power state of all Windows displays.
 */
export class ScreenControlPlatform extends MatterbridgeDynamicPlatform {
  private readonly host: ManagedScreenHostClient;
  private readonly unsubscribeDisplayState: () => void;
  private device: MatterbridgeEndpoint | undefined;
  private lastKnownDisplayState = true;

  /**
   * Creates the platform and its supervised Windows host connection.
   *
   * @param matterbridge Active Matterbridge platform API.
   * @param log Matterbridge logger.
   * @param config Persisted plugin configuration.
   * @param supervisorFactory Optional dependency injection used by tests.
   */
  constructor(
    matterbridge: PlatformMatterbridge,
    log: AnsiLogger,
    config: ScreenControlPlatformConfig,
    supervisorFactory?: SupervisorFactory,
  ) {
    super(matterbridge, log, config);

    if (
      typeof this.verifyMatterbridgeVersion !== 'function' ||
      !this.verifyMatterbridgeVersion(RequiredMatterbridgeVersion)
    ) {
      throw new Error(
        `This plugin requires Matterbridge version >= "${RequiredMatterbridgeVersion}". Current version: ${this.matterbridge.matterbridgeVersion}.`,
      );
    }

    this.host = (supervisorFactory ?? (() => this.createHostSupervisor()))();
    this.unsubscribeDisplayState = this.host.onDisplayStateChanged((isOn) => {
      this.lastKnownDisplayState = isOn;
      void this.applyMatterState(isOn).catch((error: unknown) => {
        this.log.error(
          `Failed to synchronize Windows display state: ${error instanceof Error ? error.message : String(error)}`,
        );
      });
    });
    this.log.info('Computer Screen platform initialized.');
  }

  /** Starts the Windows display device and registers it with Matterbridge. */
  override async onStart(reason?: string): Promise<void> {
    this.log.info(`Starting Computer Screen platform: ${reason ?? 'none'}`);
    await this.ready;

    const deviceName =
      typeof this.config.deviceName === 'string' &&
      this.config.deviceName.trim().length > 0
        ? this.config.deviceName.trim()
        : 'Computer Screen';
    this.device = new MatterbridgeEndpoint(onOffPlugInUnit, {
      id: 'computer-screen',
    })
      .createDefaultBridgedDeviceBasicInformationClusterServer(
        deviceName,
        DeviceSerialNumber,
        this.matterbridge.aggregatorVendorId,
        'Alone',
        'Windows Computer Screen',
        1,
        '1.0.0',
      )
      .createDefaultPowerSourceWiredClusterServer()
      .addRequiredClusters()
      .addCommandHandler('on', async () => this.setDisplayPower(true))
      .addCommandHandler('off', async () => this.setDisplayPower(false));

    await this.registerDevice(this.device);
  }

  /** Restores the current display state into persisted Matter attributes. */
  override async onConfigure(): Promise<void> {
    await super.onConfigure();
    await this.applyMatterState(this.lastKnownDisplayState);
  }

  /** Stops the Windows host and optionally unregisters the Matter device. */
  override async onShutdown(reason?: string): Promise<void> {
    this.unsubscribeDisplayState();
    await this.host.dispose();
    await super.onShutdown(reason);
    if (this.config.unregisterOnShutdown) {
      await this.unregisterAllDevices();
    }
  }

  private async setDisplayPower(isOn: boolean): Promise<void> {
    await this.host.setDisplayPower(isOn);
    this.lastKnownDisplayState = isOn;
    await this.applyMatterState(isOn);
  }

  private async applyMatterState(isOn: boolean): Promise<void> {
    if (this.device === undefined) {
      return;
    }

    await this.device.setAttribute(OnOff, 'onOff', isOn);
  }

  private createHostSupervisor(): ScreenHostSupervisor {
    const moduleDirectory = dirname(fileURLToPath(import.meta.url));
    const configuredPath =
      typeof this.config.hostExecutable === 'string' &&
      this.config.hostExecutable.trim().length > 0
        ? this.config.hostExecutable.trim()
        : 'bin/ScreenControl.Host.exe';
    const executablePath = resolve(moduleDirectory, '..', configuredPath);

    return new ScreenHostSupervisor(() => {
      const transport = new ChildProcessScreenHostTransport(executablePath);
      return new HostProtocolClient(transport, randomUUID, (error) => {
        this.log.error(error.message);
      });
    });
  }
}
