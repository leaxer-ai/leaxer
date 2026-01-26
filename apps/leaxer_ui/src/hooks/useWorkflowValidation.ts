import { useCallback, useState } from 'react';
import type { ValidationResult, ValidationError, LxrWorkflowFormat } from '../types/workflow';
import { APP_VERSION, compareVersions } from '../types/workflow';
import { apiFetch } from '@/lib/fetch';

interface UseWorkflowValidationOptions {
  baseUrl: string;
}

interface UseWorkflowValidationReturn {
  validateWorkflow: (workflow: LxrWorkflowFormat) => Promise<ValidationResult>;
  isValidating: boolean;
  lastErrors: ValidationError[];
}

/**
 * Hook for validating workflows against the backend
 */
export function useWorkflowValidation({ baseUrl }: UseWorkflowValidationOptions): UseWorkflowValidationReturn {
  const [isValidating, setIsValidating] = useState(false);
  const [lastErrors, setLastErrors] = useState<ValidationError[]>([]);

  const validateWorkflow = useCallback(
    async (workflow: LxrWorkflowFormat): Promise<ValidationResult> => {
      setIsValidating(true);
      const errors: ValidationError[] = [];

      try {
        // Check version compatibility locally first
        if (workflow.format_version) {
          const comparison = compareVersions(workflow.format_version, APP_VERSION);
          if (comparison > 0) {
            errors.push({
              type: 'version_mismatch',
              message: `This workflow was created with a newer version (${workflow.format_version}). Some features may not work correctly.`,
              can_force_open: true,
            });
          }
        }

        // Call backend validation endpoint
        try {
          const response = await apiFetch(`${baseUrl}/api/workflow/validate`, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              workflow: {
                format_version: workflow.format_version,
                requirements: workflow.requirements,
              },
            }),
          });

          if (response.ok) {
            const result = await response.json();
            if (!result.valid && result.errors) {
              errors.push(...result.errors);
            }
          } else {
            // Backend validation failed, but don't block loading
            console.warn('Backend validation failed:', response.status);
          }
        } catch (fetchError) {
          // Network error - log but don't block
          console.warn('Could not reach validation endpoint:', fetchError);
        }

        setLastErrors(errors);
        return {
          valid: errors.length === 0,
          errors,
        };
      } finally {
        setIsValidating(false);
      }
    },
    [baseUrl]
  );

  return {
    validateWorkflow,
    isValidating,
    lastErrors,
  };
}

/**
 * Client-side validation for quick checks
 */
export function validateWorkflowLocally(workflow: LxrWorkflowFormat): ValidationResult {
  const errors: ValidationError[] = [];

  // Check format identifier
  if (workflow.format !== 'lxr') {
    errors.push({
      type: 'invalid_format',
      message: 'Invalid file format: not a Leaxer workflow file',
    });
  }

  // Check required fields
  if (!workflow.graph) {
    errors.push({
      type: 'invalid_format',
      message: 'Invalid file format: missing graph data',
    });
  }

  if (!workflow.metadata?.name) {
    errors.push({
      type: 'invalid_format',
      message: 'Invalid file format: missing workflow name',
    });
  }

  // Check version compatibility
  if (workflow.format_version) {
    const comparison = compareVersions(workflow.format_version, APP_VERSION);
    if (comparison > 0) {
      errors.push({
        type: 'version_mismatch',
        message: `This workflow was created with a newer version (${workflow.format_version}). Some features may not work correctly.`,
        can_force_open: true,
      });
    }
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}
