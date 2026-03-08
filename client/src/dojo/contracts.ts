import type { DojoProvider } from "@dojoengine/core";
import type { Account, AccountInterface } from "starknet";
import { RpcProvider, CallData } from "starknet";
import { RPC_URL } from "./config";

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

  const cat_actions = {
    create_cat: async (account: Account | AccountInterface, repoHash: string) => {
      return await provider.execute(
        account,
        { contractName: "cat_actions", entrypoint: "create_cat", calldata: [repoHash] },
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

  return { cat_actions, run_actions, encounter_actions };
}
