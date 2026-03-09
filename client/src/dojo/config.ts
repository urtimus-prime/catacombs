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

// EGS (Embeddable Game Standard) contract addresses — Sepolia only for now
export const EGS_ADAPTER_ADDRESS =
  import.meta.env.VITE_EGS_ADAPTER_ADDRESS ??
  "0x0512e1ac90f210c337a7e3b25a9ec1e602de6cf1a9254ed129b9881bca814525";

export const DENSHOKAN_TOKEN_ADDRESS =
  import.meta.env.VITE_DENSHOKAN_TOKEN_ADDRESS ??
  "0x0142712722e62a38f9c40fcc904610e1a14c70125876ecaaf25d803556734467";
