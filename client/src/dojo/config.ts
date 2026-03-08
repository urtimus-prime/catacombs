import { createDojoConfig } from "@dojoengine/core";
import manifest from "./manifest_dev.json";

export const RPC_URL =
  import.meta.env.VITE_RPC_URL ?? "http://localhost:5050";

export const TORII_URL =
  import.meta.env.VITE_TORII_URL ?? "http://localhost:8080";

export const dojoConfig = createDojoConfig({ manifest, rpcUrl: RPC_URL, toriiUrl: TORII_URL });
