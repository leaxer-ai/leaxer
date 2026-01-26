/**
 * Centralized data type definitions and color mappings.
 * Single source of truth for handle/edge colors based on data type.
 */

/**
 * Data type to CSS variable mapping.
 * Keys are uppercase data type names, values are CSS variable references.
 */
export const DATA_TYPE_CSS_VARS: Record<string, string> = {
  // Complex data types
  MODEL: 'var(--color-type-model)',
  CLIP: 'var(--color-type-clip)',
  VAE: 'var(--color-type-vae)',
  CONDITIONING: 'var(--color-type-conditioning)',
  POSITIVE: 'var(--color-type-positive)',
  NEGATIVE: 'var(--color-type-negative)',
  LATENT: 'var(--color-type-latent)',
  IMAGE: 'var(--color-type-image)',
  MASK: 'var(--color-type-mask)',
  // Detailer types
  SEGS: 'var(--color-type-segs)',
  DETECTOR: 'var(--color-type-detector)',
  SAM_MODEL: 'var(--color-type-sam-model)',
  // Inference extension types
  LORA: 'var(--color-type-lora)',
  CONTROLNET: 'var(--color-type-controlnet)',
  PHOTOMAKER: 'var(--color-type-photomaker)',
  TEXT_ENCODERS: 'var(--color-type-text-encoders)',
  SAMPLER_SETTINGS: 'var(--color-type-sampler-settings)',
  CACHE_SETTINGS: 'var(--color-type-cache-settings)',
  CHROMA_SETTINGS: 'var(--color-type-chroma-settings)',
  LLM: 'var(--color-type-llm)',
  VIDEO: 'var(--color-type-video)',
  // List types
  'LIST:IMAGE': 'var(--color-type-list-image)',
  // Special types
  ANY: 'var(--color-type-any)',
  // Primitive types
  STRING: 'var(--color-type-string)',
  INTEGER: 'var(--color-type-integer)',
  FLOAT: 'var(--color-type-float)',
  BOOLEAN: 'var(--color-type-boolean)',
  BIGINT: 'var(--color-type-bigint)',
  // Default fallback
  default: 'var(--color-overlay-0)',
};

export type DataType = keyof typeof DATA_TYPE_CSS_VARS | string;

/**
 * Get the CSS variable reference for a data type color.
 * Returns var(--color-type-xxx) for use in inline styles.
 */
export function getTypeColor(dataType?: DataType): string {
  if (!dataType) return DATA_TYPE_CSS_VARS.default;
  const upperType = dataType.toUpperCase();
  return DATA_TYPE_CSS_VARS[upperType] || DATA_TYPE_CSS_VARS.default;
}

// Legacy aliases for backwards compatibility
export const DATA_TYPE_COLORS = DATA_TYPE_CSS_VARS;
export const getHandleColor = getTypeColor;
export const getEdgeColor = getTypeColor;
