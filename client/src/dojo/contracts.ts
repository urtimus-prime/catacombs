import type { DojoProvider } from "@dojoengine/core";
import type { Account, AccountInterface } from "starknet";
import { RpcProvider } from "starknet";
import { RPC_URL, EGS_ADAPTER_ADDRESS } from "./config";

// STRK token address (same on Katana, Sepolia, Mainnet)
export const STRK_ADDRESS = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";

const NS = "catacombs";
const OPTS = { tip: 0 };

// Separate read provider (bypasses DojoProvider ABI requirement)
const readProvider = new RpcProvider({ nodeUrl: RPC_URL });

async function rawCall(contractAddress: string, entrypoint: string, calldata: string[] = []) {
  const result = await readProvider.callContract({
    contractAddress,
    entrypoint,
    calldata,
  });
  return result;
}

export function setupWorld(provider: DojoProvider) {
  // Resolve contract addresses from manifest
  const manifest = provider.manifest;
  const catAddr = manifest.contracts.find((c: any) => c.tag === "catacombs-cat_actions")!.address;
  const runAddr = manifest.contracts.find((c: any) => c.tag === "catacombs-run_actions")!.address;
  const encAddr = manifest.contracts.find((c: any) => c.tag === "catacombs-encounter_actions")!.address;
  const shinyAddr = manifest.contracts.find((c: any) => c.tag === "catacombs-shiny_actions")!.address;

  const cat_actions = {
    create_cat: async (account: Account | AccountInterface, repoHash: string, appearance: string) => {
      return await provider.execute(
        account,
        { contractName: "cat_actions", entrypoint: "create_cat", calldata: [repoHash, appearance] },
        NS, OPTS,
      );
    },
    verify_cat: async (account: Account | AccountInterface, catId: number) => {
      return await provider.execute(
        account,
        { contractName: "cat_actions", entrypoint: "verify_cat", calldata: [catId] },
        NS, OPTS,
      );
    },
    get_cat: async (catId: number) => {
      return await rawCall(catAddr, "get_cat", [String(catId)]);
    },
    get_cat_appearance: async (catId: number) => {
      return await rawCall(catAddr, "get_cat_appearance", [String(catId)]);
    },
  };

  const run_actions = {
    start_run: async (account: Account | AccountInterface, catId: number) => {
      return await provider.execute(
        account,
        { contractName: "run_actions", entrypoint: "start_run", calldata: [catId] },
        NS, OPTS,
      );
    },
    choose_path: async (account: Account | AccountInterface, runId: number, nodeId: number) => {
      return await provider.execute(
        account,
        { contractName: "run_actions", entrypoint: "choose_path", calldata: [runId, nodeId] },
        NS, OPTS,
      );
    },
    abandon_run: async (account: Account | AccountInterface, runId: number) => {
      return await provider.execute(
        account,
        { contractName: "run_actions", entrypoint: "abandon_run", calldata: [runId] },
        NS, OPTS,
      );
    },
    get_run: async (runId: number) => {
      return await rawCall(runAddr, "get_run", [String(runId)]);
    },
    get_node: async (runId: number, nodeId: number) => {
      return await rawCall(runAddr, "get_node", [String(runId), String(nodeId)]);
    },
    get_node_outcome: async (runId: number, nodeId: number) => {
      return await rawCall(runAddr, "get_node_outcome", [String(runId), String(nodeId)]);
    },
  };

  const encounter_actions = {
    submit_scenario: async (
      account: Account | AccountInterface,
      runId: number, nodeId: number, scenarioHash: string,
    ) => {
      return await provider.execute(
        account,
        { contractName: "encounter_actions", entrypoint: "submit_scenario", calldata: [runId, nodeId, scenarioHash] },
        NS, OPTS,
      );
    },
    resolve_encounter: async (
      account: Account | AccountInterface,
      runId: number, nodeId: number, skillHash: string,
      result: number, hpDelta: number, xpGained: number, lootId: number,
    ) => {
      return await provider.execute(
        account,
        {
          contractName: "encounter_actions",
          entrypoint: "resolve_encounter",
          calldata: [runId, nodeId, skillHash, result, hpDelta, xpGained, lootId],
        },
        NS, OPTS,
      );
    },
  };

  const shiny_actions = {
    buy_shinies: async (account: Account | AccountInterface, amount: number) => {
      // Multicall: approve STRK spend + buy shinies in one tx
      const cost = BigInt(amount) * BigInt("1000000000000000000"); // amount * 1e18
      const costLow = "0x" + (cost & ((1n << 128n) - 1n)).toString(16);
      const costHigh = "0x" + (cost >> 128n).toString(16);

      return await account.execute([
        {
          contractAddress: STRK_ADDRESS,
          entrypoint: "approve",
          calldata: [shinyAddr, costLow, costHigh],
        },
        {
          contractAddress: shinyAddr,
          entrypoint: "buy_shinies",
          calldata: [String(amount)],
        },
      ]);
    },
    get_balance: async (owner: string) => {
      return await rawCall(shinyAddr, "get_balance", [owner]);
    },
    get_strk_balance: async (owner: string) => {
      return await rawCall(STRK_ADDRESS, "balance_of", [owner]);
    },
  };

  // EGS adapter — standalone contract (not a Dojo system)
  const egs_adapter = {
    // Mint an EGS game token and bind it to a run in one call
    mint_and_register: async (account: Account | AccountInterface, playerAddress: string, runId: number) => {
      return await account.execute([
        {
          contractAddress: EGS_ADAPTER_ADDRESS,
          entrypoint: "mint_and_register",
          calldata: [playerAddress, String(runId)],
        },
      ]);
    },

    // Read: get run_id for a token
    get_run_for_token: async (tokenId: string) => {
      return await rawCall(EGS_ADAPTER_ADDRESS, "get_run_for_token", [tokenId]);
    },

    // Read: get token_id for a run
    get_token_for_run: async (runId: number) => {
      return await rawCall(EGS_ADAPTER_ADDRESS, "get_token_for_run", [String(runId)]);
    },
  };

  return { cat_actions, run_actions, encounter_actions, shiny_actions, egs_adapter };
}
