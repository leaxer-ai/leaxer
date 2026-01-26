import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { getCurrentWindow } from '@tauri-apps/api/window'
import '@xyflow/react/dist/style.css'
import './index.css'
import App from './App.tsx'

// Show window after content is fully loaded (prevents white flash on Tauri)
// Only run in Tauri environment
if ((window as Window & { __TAURI_INTERNALS__?: unknown }).__TAURI_INTERNALS__) {
  window.addEventListener('load', () => {
    setTimeout(() => {
      getCurrentWindow().show()
    }, 100)
  })
}

// Clean up old localStorage keys that are no longer used
const cleanupOldLocalStorage = () => {
  // Remove old graphStore key (now using workflowStore)
  localStorage.removeItem('leaxer-graph');

  // Check if workflowStore data is corrupted and reset if needed
  try {
    const workflowData = localStorage.getItem('leaxer-workflows');
    if (workflowData) {
      const parsed = JSON.parse(workflowData);
      // Validate basic structure
      if (!parsed.state || !Array.isArray(parsed.state.tabs)) {
        console.warn('[Leaxer] Invalid workflow data, clearing...');
        localStorage.removeItem('leaxer-workflows');
      }
    }
  } catch {
    console.warn('[Leaxer] Corrupted workflow data, clearing...');
    localStorage.removeItem('leaxer-workflows');
  }
};

cleanupOldLocalStorage();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)

