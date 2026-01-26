/**
 * Deep clone utility for creating independent copies of objects.
 *
 * Uses structuredClone when available (modern browsers, Node 17+),
 * which is significantly faster than JSON.parse(JSON.stringify())
 * and handles more edge cases (circular references, typed arrays, etc).
 *
 * @example
 * const copy = deepClone(original);
 * // copy is a completely independent deep copy
 */
export function deepClone<T>(obj: T): T {
  // Handle primitives and null/undefined
  if (obj === null || typeof obj !== 'object') {
    return obj;
  }

  // Use structuredClone for optimal performance
  // Supported in: Chrome 98+, Firefox 94+, Safari 15.4+, Node 17+
  return structuredClone(obj);
}
