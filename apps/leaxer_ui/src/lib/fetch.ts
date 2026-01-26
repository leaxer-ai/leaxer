/**
 * Unified fetch wrapper that uses Tauri's HTTP plugin when running in Tauri,
 * bypassing browser CORS/PNA restrictions for localhost requests.
 */

import { fetch as tauriFetch } from '@tauri-apps/plugin-http';

// Check if we're running in Tauri
const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

/**
 * Fetch wrapper that automatically uses Tauri HTTP plugin when in Tauri environment.
 * This bypasses browser CORS and Private Network Access restrictions.
 */
export async function apiFetch(
  input: string | URL | Request,
  init?: RequestInit
): Promise<Response> {
  if (isTauri) {
    // Use Tauri's HTTP plugin which bypasses browser restrictions
    return tauriFetch(input, init);
  }
  // Fall back to native fetch for browser/dev mode
  return fetch(input, init);
}

/**
 * Convenience method for JSON API calls
 */
export async function apiJson<T>(
  url: string,
  options?: RequestInit
): Promise<T> {
  const response = await apiFetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...options?.headers,
    },
  });

  if (!response.ok) {
    throw new Error(`API error: ${response.status} ${response.statusText}`);
  }

  return response.json();
}
