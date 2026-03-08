import type { PropsWithChildren } from "react";
import { sepolia } from "@starknet-react/chains";
import { Chain } from "@starknet-react/chains";
import {
  jsonRpcProvider,
  StarknetConfig,
  MockConnector,
  type Connector,
} from "@starknet-react/core";
import { Account, RpcProvider, constants } from "starknet";
import ControllerConnector from "@cartridge/connector/controller";
import { RPC_URL } from "./dojo/config";

const CHAIN = import.meta.env.VITE_CHAIN ?? "katana";

// --- Katana (local dev) ---
const KATANA_CHAIN_ID = "0x4b4154414e41";
const SLOT_CHAIN_ID = "0x57505f43415441434f4d4253";

const katana: Chain = {
  id: BigInt(KATANA_CHAIN_ID),
  name: "Katana",
  network: "katana",
  testnet: true,
  nativeCurrency: {
    address: "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
    name: "Stark",
    symbol: "STRK",
    decimals: 18,
  },
  rpcUrls: {
    default: { http: [RPC_URL] },
    public: { http: [RPC_URL] },
  },
  paymasterRpcUrls: {
    avnu: { http: [RPC_URL] },
  },
} as Chain;

const KATANA_ACCOUNTS = [
  {
    address: "0x127fd5f1fe78a71f8bcd1fec63e3fe2f0486b6ecd5c86a0466c3a21fa5cfcec",
    privateKey: "0xc5b2fcab997346f3ea1c00b002ecf6f382c5f9c9659a3894eb783c5320f912",
  },
  {
    address: "0x13d9ee239f33fea4f8785b9e3870ade909e20a9599ae7cd62c1c292b73af1b7",
    privateKey: "0x1c9053c053edf324aec366a34c6901b1095b07af69495bffec7d7fe21effb1b",
  },
];

function createKatanaBurner(): Connector {
  const starkProvider = new RpcProvider({ nodeUrl: RPC_URL });
  const accounts = KATANA_ACCOUNTS.map(
    (a) =>
      new Account({
        provider: starkProvider,
        address: a.address,
        signer: a.privateKey,
      }),
  );
  return new MockConnector({
    accounts: { sepolia: accounts, mainnet: accounts },
    options: { id: "katana-burner", name: "Katana Burner" },
  });
}

// --- Slot / Sepolia (production) ---
function createController(): Connector {
  const chainId = CHAIN === "slot" ? SLOT_CHAIN_ID : constants.StarknetChainId.SN_SEPOLIA;
  return new ControllerConnector({
    chains: [{ rpcUrl: RPC_URL }],
    defaultChainId: chainId,
  }) as unknown as Connector;
}

// --- Provider setup ---
const isRemote = CHAIN === "sepolia" || CHAIN === "slot";

const slotChain: Chain = {
  id: BigInt(SLOT_CHAIN_ID),
  name: "Slot Katana",
  network: "slot",
  testnet: true,
  nativeCurrency: {
    address: "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
    name: "Stark",
    symbol: "STRK",
    decimals: 18,
  },
  rpcUrls: {
    default: { http: [RPC_URL] },
    public: { http: [RPC_URL] },
  },
  paymasterRpcUrls: {
    avnu: { http: [RPC_URL] },
  },
} as Chain;

const chain = CHAIN === "sepolia" ? sepolia : CHAIN === "slot" ? slotChain : katana;
const connectors = [isRemote ? createController() : createKatanaBurner()];
const provider = jsonRpcProvider({ rpc: () => ({ nodeUrl: RPC_URL }) });

export default function StarknetProvider({ children }: PropsWithChildren) {
  return (
    <StarknetConfig
      chains={[chain]}
      provider={provider}
      connectors={connectors}
    >
      {children}
    </StarknetConfig>
  );
}
