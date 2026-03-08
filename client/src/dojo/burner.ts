import { MockConnector } from "@starknet-react/core";
import { Account, RpcProvider } from "starknet";

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

export function createBurnerConnector(rpcUrl: string) {
  const provider = new RpcProvider({ nodeUrl: rpcUrl });
  const accounts = KATANA_ACCOUNTS.map(
    (a) => new Account({
      provider,
      address: a.address,
      signer: a.privateKey,
    })
  );
  return new MockConnector({
    accounts: {
      sepolia: accounts,
      mainnet: accounts,
    },
    options: {
      id: "katana-burner",
      name: "Katana Burner",
    },
  });
}
