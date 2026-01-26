import js from '@eslint/js'
import globals from 'globals'
import reactHooks from 'eslint-plugin-react-hooks'
import reactRefresh from 'eslint-plugin-react-refresh'
import tseslint from 'typescript-eslint'
import { defineConfig, globalIgnores } from 'eslint/config'

export default defineConfig([
  globalIgnores(['dist']),
  {
    files: ['**/*.{ts,tsx}'],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      ecmaVersion: 2020,
      globals: globals.browser,
    },
    rules: {
      // Allow setState in useEffect for valid patterns like resetting state on prop changes
      'react-hooks/set-state-in-effect': 'off',
      // Allow unused vars with underscore prefix (common for destructuring to remove props)
      '@typescript-eslint/no-unused-vars': ['error', {
        argsIgnorePattern: '^_',
        varsIgnorePattern: '^_',
        caughtErrorsIgnorePattern: '^_',
      }],
      // Disable refs rule that conflicts with valid patterns
      'react-hooks/refs': 'off',
      // Incompatible library warnings are not actionable
      'react-hooks/incompatible-library': 'off',
      // Preserve manual memoization is too strict
      'react-hooks/preserve-manual-memoization': 'off',
      // Purity rule is too strict for common patterns like Date.now() initialization
      'react-hooks/purity': 'off',
      // Immutability rule can conflict with valid patterns
      'react-hooks/immutability': 'off',
      // Allow escaping forward slashes in regex literals (needed for URL patterns)
      'no-useless-escape': 'off',
    },
  },
])
