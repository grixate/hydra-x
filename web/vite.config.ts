import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import path from "node:path";

const proxyTarget = process.env.VITE_API_PROXY_TARGET ?? "http://localhost:4000";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
  server: {
    host: "0.0.0.0",
    port: 3000,
    proxy: {
      "/api": proxyTarget,
      "/socket": {
        target: proxyTarget,
        ws: true,
      },
      "/login": proxyTarget,
      "/logout": proxyTarget,
    },
  },
});
