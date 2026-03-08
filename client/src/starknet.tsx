import type { PropsWithChildren } from "react";
import { Chain } from "@starknet-react/chains";
import { jsonRpcProvider, StarknetConfig, MockConnector } from "@starknet-react/core";
import { Account, RpcProvider } from "starknet";
import { RPC_URL } from "./dojo/config";

const KATANA_CHAIN_ID = "0x4b4154414e41";

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

// Katana predeployed accounts
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

const starkProvider = new RpcProvider({ nodeUrl: RPC_URL });
const accounts = KATANA_ACCOUNTS.map(
  (a) =>
    new Account({
      provider: starkProvider,
      address: a.address,
      signer: a.privateKey,
    }),
);

const katanaBurner = new MockConnector({
  accounts: { sepolia: accounts, mainnet: accounts },
  options: { id: "katana-burner", name: "Katana Burner" },
});

const provider = jsonRpcProvider({ rpc: () => ({ nodeUrl: RPC_URL }) });

export default function StarknetProvider({ children }: PropsWithChildren) {
  return (
    <StarknetConfig
      chains={[katana]}
      provider={provider}
      connectors={[katanaBurner]}
    >
      {children}
    </StarknetConfig>
  );
}
