# AGENTS.md - Rules for AI Agents

## Before Committing

**ALWAYS run these checks before committing:**

### Backend (Elixir)
```bash
cd ~/Work/leaxer
mix format --check-formatted
mix credo --strict
mix compile --warnings-as-errors
mix test
```

### Frontend (React/TypeScript)
```bash
npm run lint
npm run format:check  # or prettier --check
npm run build
npm test
```

### Quick All-in-One
```bash
# Backend
mix format --check-formatted && mix credo && mix compile --warnings-as-errors && mix test

# Frontend
npm run lint && npm run build
```

## Commit Rules
- Use **conventional commits**: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
- Include scope when relevant: `feat(chat):`, `fix(llm):`
- Only commit if ALL checks pass
- Push only after confirming with user (unless explicitly told otherwise)

## Code Style
- Follow existing patterns in the codebase
- **Glassmorphic UI** — use glass/frosted effects, blur, transparency
- Match existing component styling
- Keep Phoenix contexts clean
- Use TypeScript strictly (no `any`)

## Architecture
- Backend: Elixir/Phoenix umbrella app (`apps/leaxer_core`)
- Frontend: React + Vite (`apps/leaxer_ui`)
- Desktop: Tauri (`apps/leaxer_desktop`)
- Use PubSub for real-time updates
- Use Phoenix Channels for WebSocket communication
