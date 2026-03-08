import type { PropsWithChildren } from "react";
import { mainnet, sepolia } from "@starknet-react/chains";
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
import { dojoConfig } from "./dojo/config";

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

// --- Controller (Sepolia / Mainnet) ---
function getContractAddress(tag: string): string {
  return dojoConfig.manifest.contracts.find((c: any) => c.tag === tag)?.address ?? "0x0";
}

function createController(): Connector {
  const chainId = CHAIN === "mainnet" ? constants.StarknetChainId.SN_MAIN : constants.StarknetChainId.SN_SEPOLIA;
  const catAddr = getContractAddress("catacombs-cat_actions");
  const runAddr = getContractAddress("catacombs-run_actions");
  const encAddr = getContractAddress("catacombs-encounter_actions");

  return new ControllerConnector({
    chains: [{ rpcUrl: RPC_URL }],
    defaultChainId: chainId,
    policies: {
      contracts: {
        [catAddr]: {
          methods: [
            { name: "Create Cat", entrypoint: "create_cat", description: "Create a new cat for your roster" },
            { name: "Verify Cat", entrypoint: "verify_cat", description: "Verify a cat's identity" },
          ],
        },
        [runAddr]: {
          methods: [
            { name: "Start Run", entrypoint: "start_run", description: "Begin a new catacomb run" },
            { name: "Choose Path", entrypoint: "choose_path", description: "Move to a connected node" },
            { name: "Abandon Run", entrypoint: "abandon_run", description: "Abandon the current run" },
          ],
        },
        [encAddr]: {
          methods: [
            { name: "Submit Scenario", entrypoint: "submit_scenario", description: "Submit a scenario for an encounter" },
            { name: "Resolve Encounter", entrypoint: "resolve_encounter", description: "Resolve an encounter outcome" },
          ],
        },
      },
    },
  }) as unknown as Connector;
}

// --- Provider setup ---
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

const chain = CHAIN === "mainnet" ? mainnet : CHAIN === "sepolia" ? sepolia : CHAIN === "slot" ? slotChain : katana;
// Controller works on Sepolia and Mainnet; Slot/Katana use burner
const connectors = [CHAIN === "sepolia" || CHAIN === "mainnet" ? createController() : createKatanaBurner()];
const provider = jsonRpcProvider({ rpc: () => ({ nodeUrl: RPC_URL }) });

export default function StarknetProvider({ children }: PropsWithChildren) {
  return (
    <StarknetConfig
      chains={[chain]}
      provider={provider}
      connectors={connectors}
      autoConnect
    >
      {children}
    </StarknetConfig>
  );
}
