# Hydra Product Web

Standalone React/Vite frontend for the product-layer UI.

## Local development

1. Start the Phoenix backend in the repo root:

```sh
mix phx.server
```

2. Install frontend dependencies:

```sh
cd web
npm install
```

3. Start the product app:

```sh
npm run dev
```

The Vite dev server proxies `/api`, `/socket`, `/login`, and `/logout` to `http://localhost:4000` by default, so the frontend can reuse the Phoenix operator session and authenticated channels without separate CORS setup.

If your backend runs elsewhere, set `VITE_API_PROXY_TARGET`.
