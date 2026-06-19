import path from 'node:path';

import { MatterbridgeEndpoint, type PlatformMatterbridge } from 'matterbridge';
import { AnsiLogger } from 'matterbridge/logger';
import { VendorId } from 'matterbridge/matter';
import { OnOff } from 'matterbridge/matter/clusters';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import {
  ScreenControlPlatform,
  type ScreenControlPlatformConfig,
} from '../src/module.js';
import type { ManagedScreenHostClient } from '../src/screen-host-supervisor.js';

describe('ScreenControlPlatform', () => {
  const addedDevices: MatterbridgeEndpoint[] = [];
  const addBridgedEndpoint = vi.fn(
    async (_pluginName: string, device: MatterbridgeEndpoint) => {
      addedDevices.push(device);
    },
  );
  const removeBridgedEndpoint = vi.fn(
    async (_pluginName: string, _device: MatterbridgeEndpoint) => {},
  );
  const removeAllBridgedEndpoints = vi.fn(async (_pluginName: string) => {});
  const registerVirtualDevice = vi.fn(
    async (
      _name: string,
      _type: 'light' | 'outlet' | 'switch' | 'mounted_switch',
      _callback: () => Promise<void>,
    ) => {},
  );

  beforeEach(() => {
    addedDevices.length = 0;
    vi.clearAllMocks();
  });

  it('registers Computer Screen and leaves command attribute updates to Matterbridge', async () => {
    const supervisor = new RecordingSupervisor();
    const platform = new ScreenControlPlatform(
      mockMatterbridge,
      mockLog,
      mockConfig,
      () => supervisor,
    );
    // Matterbridge exposes this hook to its plugin loader; tests provide the same registration callbacks.
    // @ts-expect-error Matterbridge intentionally keeps the loader hook non-public.
    platform.setMatterNode(
      addBridgedEndpoint,
      removeBridgedEndpoint,
      removeAllBridgedEndpoints,
      registerVirtualDevice,
    );

    await platform.onStart('test');

    expect(addedDevices).toHaveLength(1);
    const device = addedDevices[0];
    expect(device?.deviceName).toBe('Computer Screen');
    expect(device).toBeDefined();
    const setAttribute = vi
      .spyOn(device!, 'setAttribute')
      .mockResolvedValue(true);
    await device!.executeCommandHandler('on', {}, 'onOff', {} as never, device!);
    expect(supervisor.requestedStates).toEqual([true]);
    expect(setAttribute).not.toHaveBeenCalled();
  });

  it('updates the Matter attribute when Windows publishes a display state', async () => {
    const supervisor = new RecordingSupervisor();
    const platform = new ScreenControlPlatform(
      mockMatterbridge,
      mockLog,
      mockConfig,
      () => supervisor,
    );
    // @ts-expect-error Matterbridge intentionally keeps the loader hook non-public.
    platform.setMatterNode(
      addBridgedEndpoint,
      removeBridgedEndpoint,
      removeAllBridgedEndpoints,
      registerVirtualDevice,
    );
    await platform.onStart('test');
    const device = addedDevices[0];
    expect(device).toBeDefined();
    const setAttribute = vi
      .spyOn(device!, 'setAttribute')
      .mockResolvedValue(true);

    supervisor.emitState(false);

    await vi.waitFor(() => {
      expect(setAttribute).toHaveBeenCalledWith(OnOff, 'onOff', false);
    });
  });

  it('does not start an attribute transaction from a display event during a command', async () => {
    let completeCommand: (() => void) | undefined;
    const commandGate = new Promise<void>((resolve) => {
      completeCommand = resolve;
    });
    const supervisor = new RecordingSupervisor(undefined, commandGate);
    const platform = new ScreenControlPlatform(
      mockMatterbridge,
      mockLog,
      mockConfig,
      () => supervisor,
    );
    // @ts-expect-error Matterbridge intentionally keeps the loader hook non-public.
    platform.setMatterNode(
      addBridgedEndpoint,
      removeBridgedEndpoint,
      removeAllBridgedEndpoints,
      registerVirtualDevice,
    );
    await platform.onStart('test');
    const device = addedDevices[0];
    expect(device).toBeDefined();
    const setAttribute = vi
      .spyOn(device!, 'setAttribute')
      .mockResolvedValue(true);

    const command = device!.executeCommandHandler(
      'off',
      {},
      'onOff',
      {} as never,
      device!,
    );
    await vi.waitFor(() => {
      expect(supervisor.requestedStates).toEqual([false]);
    });
    supervisor.emitState(true);
    await Promise.resolve();

    expect(setAttribute).not.toHaveBeenCalled();

    completeCommand?.();
    await command;
  });

  it('does not update Matter when the Windows host rejects a command', async () => {
    const supervisor = new RecordingSupervisor(
      new Error('Windows host rejected the command.'),
    );
    const platform = new ScreenControlPlatform(
      mockMatterbridge,
      mockLog,
      mockConfig,
      () => supervisor,
    );
    // @ts-expect-error Matterbridge intentionally keeps the loader hook non-public.
    platform.setMatterNode(
      addBridgedEndpoint,
      removeBridgedEndpoint,
      removeAllBridgedEndpoints,
      registerVirtualDevice,
    );
    await platform.onStart('test');
    const device = addedDevices[0];
    expect(device).toBeDefined();
    const setAttribute = vi
      .spyOn(device!, 'setAttribute')
      .mockResolvedValue(true);

    await expect(
      device!.executeCommandHandler('off', {}, 'onOff', {} as never, device!),
    ).rejects.toThrow('Windows host rejected the command.');

    expect(setAttribute).not.toHaveBeenCalled();
  });

  it('restores the latest Windows state during configure and disposes on shutdown', async () => {
    const supervisor = new RecordingSupervisor();
    const platform = new ScreenControlPlatform(
      mockMatterbridge,
      mockLog,
      mockConfig,
      () => supervisor,
    );
    // @ts-expect-error Matterbridge intentionally keeps the loader hook non-public.
    platform.setMatterNode(
      addBridgedEndpoint,
      removeBridgedEndpoint,
      removeAllBridgedEndpoints,
      registerVirtualDevice,
    );
    supervisor.emitState(false);
    await platform.onStart('test');
    const device = addedDevices[0];
    expect(device).toBeDefined();
    const setAttribute = vi
      .spyOn(device!, 'setAttribute')
      .mockResolvedValue(true);

    await platform.onConfigure();
    await platform.onShutdown('test');

    expect(setAttribute).toHaveBeenCalledWith(OnOff, 'onOff', false);
    expect(supervisor.disposeCount).toBe(1);
    expect(removeAllBridgedEndpoints).not.toHaveBeenCalled();
  });
});

class RecordingSupervisor implements ManagedScreenHostClient {
  readonly requestedStates: boolean[] = [];
  disposeCount = 0;
  private readonly listeners = new Set<(isOn: boolean) => void>();

  constructor(
    private readonly commandError?: Error,
    private readonly commandGate?: Promise<void>,
  ) {}

  async setDisplayPower(isOn: boolean): Promise<void> {
    this.requestedStates.push(isOn);
    await this.commandGate;
    if (this.commandError !== undefined) {
      throw this.commandError;
    }
  }

  onDisplayStateChanged(listener: (isOn: boolean) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async dispose(): Promise<void> {
    this.disposeCount++;
  }

  emitState(isOn: boolean): void {
    for (const listener of this.listeners) {
      listener(isOn);
    }
  }
}

const mockLog = {
  fatal: vi.fn(),
  error: vi.fn(),
  warn: vi.fn(),
  notice: vi.fn(),
  info: vi.fn(),
  debug: vi.fn(),
} as unknown as AnsiLogger;

const mockConfig: ScreenControlPlatformConfig = {
  name: 'matterbridge-google-home-screen-control',
  type: 'DynamicPlatform',
  version: '1.0.0',
  debug: false,
  unregisterOnShutdown: false,
  deviceName: 'Computer Screen',
  hostExecutable: 'bin/ScreenControl.Host.exe',
};

const mockMatterbridge: PlatformMatterbridge = {
  systemInformation: {
    interfaceName: 'Ethernet',
    macAddress: 'aa:bb:cc:dd:ee:ff',
    ipv4Address: '192.168.86.45',
    ipv6Address: 'fe80::1',
    osRelease: 'Windows 11',
    nodeVersion: '24.14.0',
    hostname: 'computer',
    user: 'test',
    osType: 'Windows_NT',
    osPlatform: 'win32',
    osArch: 'x64',
    totalMemory: '0 B',
    freeMemory: '0 B',
    systemUptime: '0s',
    processUptime: '0s',
    cpuUsage: '0%',
    processCpuUsage: '0%',
    rss: '0 B',
    heapTotal: '0 B',
    heapUsed: '0 B',
  },
  uuid: '00000000-0000-0000-0000-000000000000',
  rootDirectory: path.join('.cache', 'test'),
  homeDirectory: path.join('.cache', 'test'),
  matterbridgeDirectory: path.join('.cache', 'test', '.matterbridge'),
  matterbridgePluginDirectory: path.join('.cache', 'test', 'Matterbridge'),
  matterbridgeCertDirectory: path.join('.cache', 'test', '.mattercert'),
  globalModulesDirectory: path.join('.cache', 'test', 'node_modules'),
  matterbridgeVersion: '3.9.0',
  matterbridgeLatestVersion: '3.9.0',
  matterbridgeDevVersion: '3.9.0',
  frontendVersion: '3.9.0',
  bridgeMode: 'bridge',
  restartMode: '',
  virtualMode: 'outlet',
  aggregatorVendorId: VendorId(0xfff1),
  aggregatorVendorName: 'Matterbridge',
  aggregatorProductId: 0x8000,
  aggregatorProductName: 'Matterbridge Test Aggregator',
};
