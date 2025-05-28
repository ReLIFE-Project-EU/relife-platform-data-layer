import react from "@vitejs/plugin-react";
import process from "process";
import { defineConfig } from "vite";

const serviceApiHost = process.env.VITE_SERVICE_API_HOST || "localhost";
const serviceApiPort = parseInt(process.env.VITE_SERVICE_API_PORT) || 9090;

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 10100,
    proxy: {
      "/api": {
        target: `http://${serviceApiHost}:${serviceApiPort}`,
        changeOrigin: true,
        secure: false,
        rewrite: (path) => path.replace(/^\/api/, ""),
        configure: (proxy) => {
          proxy.on("error", (err) => {
            console.error("[Proxy Error]", err.message, {
              stack: err.stack,
              timestamp: new Date().toISOString(),
            });
          });

          proxy.on("proxyReq", (proxyReq, req) => {
            console.log("[Proxy Request]", {
              method: req.method,
              url: req.url,
              timestamp: new Date().toISOString(),
            });
          });

          proxy.on("proxyRes", (proxyRes, req) => {
            console.log("[Proxy Response]", {
              status: proxyRes.statusCode,
              statusMessage: proxyRes.statusMessage,
              url: req.url,
              timestamp: new Date().toISOString(),
            });
          });
        },
      },
    },
  },
});
