import { createDojoConfig } from "@dojoengine/core";
import manifest_dev from "./manifest_dev.json";
import manifest_sepolia from "./manifest_sepolia.json";

export const CHAIN = import.meta.env.VITE_CHAIN ?? "katana";

export const RPC_URL =
  import.meta.env.VITE_RPC_URL ?? "http://localhost:5050";

export const TORII_URL =
  import.meta.env.VITE_TORII_URL ?? "http://localhost:8080";

const manifest = CHAIN === "sepolia" || CHAIN === "mainnet" ? manifest_sepolia : manifest_dev;

export const dojoConfig = createDojoConfig({ manifest, rpcUrl: RPC_URL, toriiUrl: TORII_URL });
