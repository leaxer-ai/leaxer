/**
 * Sidecar lifecycle management for the Leaxer Elixir backend.
 *
 * The sidecar is automatically started by Tauri when the app launches.
 * This module provides utilities to check status and restart if needed.
 */

import { Command } from '@tauri-apps/plugin-shell';

const BACKEND_URL = 'http://localhost:4000';
const HEALTH_CHECK_INTERVAL = 5000;

export interface SidecarStatus {
  running: boolean;
  healthy: boolean;
  url: string;
}

/**
 * Check if the backend is healthy by pinging the health endpoint.
 */
export async function checkHealth(): Promise<boolean> {
  try {
    const response = await fetch(`${BACKEND_URL}/api/health`, {
      method: 'GET',
      signal: AbortSignal.timeout(2000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

/**
 * Wait for the backend to become healthy.
 */
export async function waitForBackend(
  maxAttempts = 30,
  intervalMs = 1000
): Promise<boolean> {
  for (let i = 0; i < maxAttempts; i++) {
    if (await checkHealth()) {
      return true;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  return false;
}

/**
 * Get the current sidecar status.
 */
export async function getSidecarStatus(): Promise<SidecarStatus> {
  const healthy = await checkHealth();
  return {
    running: healthy, // If healthy, it's running
    healthy,
    url: BACKEND_URL,
  };
}

/**
 * Restart the sidecar (requires Tauri restart).
 * This is a placeholder - actual restart requires app restart.
 */
export function restartSidecar(): void {
  console.warn(
    'Sidecar restart requires app restart. Please restart Leaxer.'
  );
}

/**
 * Start periodic health checks.
 * Returns a cleanup function to stop the checks.
 */
export function startHealthMonitor(
  onStatusChange: (status: SidecarStatus) => void
): () => void {
  let lastStatus: SidecarStatus | null = null;

  const check = async () => {
    const status = await getSidecarStatus();

    // Only notify if status changed
    if (
      !lastStatus ||
      lastStatus.healthy !== status.healthy ||
      lastStatus.running !== status.running
    ) {
      lastStatus = status;
      onStatusChange(status);
    }
  };

  // Initial check
  check();

  // Periodic checks
  const interval = setInterval(check, HEALTH_CHECK_INTERVAL);

  return () => clearInterval(interval);
}
