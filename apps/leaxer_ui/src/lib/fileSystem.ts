/**
 * File System Abstraction Layer
 *
 * Provides a unified API for file operations that works with:
 * - Backend API (browser/docker) - saves via Phoenix backend to ~/Documents/Leaxer/workflows
 * - Tauri (desktop app) - can additionally use native file dialogs for import/export
 */

import { apiFetch } from '@/lib/fetch';

// ============================================================================
// API Configuration
// ============================================================================

const API_BASE = import.meta.env.VITE_API_URL || 'http://localhost:4000';

// ============================================================================
// Types
// ============================================================================

export interface WorkflowFile {
  name: string;
  filename: string;
  modified_at: string;
}

export interface SaveWorkflowResult {
  success: boolean;
  name: string;
  filename: string;
  path: string;
}

// ============================================================================
// Tauri Detection
// ============================================================================

export const isTauri = () => {
  return typeof window !== 'undefined' && '__TAURI__' in window;
};

// ============================================================================
// Backend API - Workflow Operations
// ============================================================================

/**
 * List all saved workflows from the backend
 */
export async function listWorkflows(): Promise<WorkflowFile[]> {
  try {
    const response = await apiFetch(`${API_BASE}/api/workflows`);
    if (!response.ok) {
      throw new Error(`Failed to list workflows: ${response.statusText}`);
    }
    const data = await response.json();
    return data.workflows || [];
  } catch (error) {
    console.error('Failed to list workflows:', error);
    return [];
  }
}

/**
 * Load a workflow by name from the backend
 */
export async function loadWorkflow(name: string): Promise<unknown> {
  const response = await apiFetch(`${API_BASE}/api/workflows/${encodeURIComponent(name)}`);
  if (!response.ok) {
    if (response.status === 404) {
      throw new Error(`Workflow '${name}' not found`);
    }
    throw new Error(`Failed to load workflow: ${response.statusText}`);
  }
  return await response.json();
}

/**
 * Save a workflow to the backend (saves to ~/Documents/Leaxer/workflows)
 */
export async function saveWorkflow(name: string, workflow: unknown): Promise<SaveWorkflowResult> {
  const response = await apiFetch(`${API_BASE}/api/workflows`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ name, workflow }),
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.error || `Failed to save workflow: ${response.statusText}`);
  }

  return await response.json();
}

/**
 * Delete a workflow from the backend
 */
export async function deleteWorkflow(name: string): Promise<void> {
  const response = await apiFetch(`${API_BASE}/api/workflows/${encodeURIComponent(name)}`, {
    method: 'DELETE',
  });

  if (!response.ok) {
    if (response.status === 404) {
      throw new Error(`Workflow '${name}' not found`);
    }
    throw new Error(`Failed to delete workflow: ${response.statusText}`);
  }
}

// ============================================================================
// Import/Export (Browser File Operations)
// ============================================================================

/**
 * Import a workflow from a local file (opens file picker)
 * Returns the parsed workflow content
 */
export async function importWorkflowFromFile(): Promise<{ name: string; workflow: unknown } | null> {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.lxr,.json';

    input.onchange = async (e) => {
      const file = (e.target as HTMLInputElement).files?.[0];
      if (!file) {
        resolve(null);
        return;
      }

      try {
        const content = await file.text();
        const workflow = JSON.parse(content);
        const name = file.name.replace(/\.(lxr|json)$/, '');
        resolve({ name, workflow });
      } catch (error) {
        console.error('Failed to parse workflow file:', error);
        resolve(null);
      }
    };

    input.oncancel = () => resolve(null);
    input.click();
  });
}

/**
 * Export/download a workflow as a file
 */
export function exportWorkflowToFile(filename: string, workflow: unknown): void {
  const content = JSON.stringify(workflow, null, 2);
  const blob = new Blob([content], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename.endsWith('.lxr') ? filename : `${filename}.lxr`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Extract filename from path
 */
export function getFileName(path: string): string {
  return path.split('/').pop()?.split('\\').pop() || 'Untitled';
}

/**
 * Extract filename without extension
 */
export function getFileNameWithoutExtension(path: string): string {
  const name = getFileName(path);
  const lastDot = name.lastIndexOf('.');
  return lastDot > 0 ? name.slice(0, lastDot) : name;
}

/**
 * Sanitize a name for use as a filename
 */
export function sanitizeFilename(name: string): string {
  return name
    .replace(/[<>:"/\\|?*]/g, '-')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .toLowerCase();
}
