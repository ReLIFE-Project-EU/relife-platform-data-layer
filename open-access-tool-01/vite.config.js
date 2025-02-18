import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    port: 10100,
    proxy: {
      "/auth": {
        target: "http://localhost:10200",
        changeOrigin: true,
      },
    },
  },
});
