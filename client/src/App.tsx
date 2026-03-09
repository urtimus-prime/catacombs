import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useAccount, useConnect, useDisconnect } from "@starknet-react/core";
import { useDojoSDK } from "@dojoengine/sdk/react";
import { RpcProvider } from "starknet";
import { NODE_TYPES, RUN_STATUS } from "./dojo/models";
import { RPC_URL, CHAIN } from "./dojo/config";
import "./App.css";

const EXPLORER_URL = import.meta.env.VITE_EXPLORER_URL ?? "";
// Bump CAT_VIEWER_VERSION when rebuilding Godot, then upload to R2 under the new path
const CAT_VIEWER_VERSION = "v2";
const CAT_VIEWER_BASE = import.meta.env.DEV
  ? "/cat-viewer"
  : `https://pub-f5ae3b0da5d447b4b4f6a8cd2270c415.r2.dev/cat-viewer/${CAT_VIEWER_VERSION}`;

const NODE_ICONS: Record<string, string> = {
  Start: "\u25C9", Treasure: "\u2666", Rest: "\u2665", Boss: "\u2620",
};

// Skill glyphs — clean text symbols, no emoji variation selectors
const SKILL_ICONS: Record<string, string> = {
  combat: "\u2694", stealth: "\u25C8", charm: "\u2661",
  agility: "\u2192", arcane: "\u2726", survival: "\u2618",
};

interface Toast {
  id: number;
  message: string;
  type: "success" | "error" | "info";
  timestamp: number;
}

interface CatState {
  id: number; owner: string; hp: number; max_hp: number;
  level: number; xp: number; attack: number; defense: number;
  speed: number; luck: number; alive: boolean;
  runs_completed: number; runs_failed: number;
}

interface RunState {
  id: number; cat_id: number; current_node_id: number;
  node_count: number; status: number;
  score: number; nodes_visited: number;
}

interface NodeState {
  node_id: number; column: number; row: number; node_type: number;
  connections: number; resolved: boolean;
  skill_tag_1: string; skill_tag_2: string; difficulty: number;
}

interface RunLogEntry {
  node_id: number;
  node_type: string;
  skill_tag: string;
  cat_stat: number;
  roll: number;
  difficulty: number;
  result: "success" | "partial" | "failure" | "n/a";
  hp_delta: number;
  xp_gained: number;
  score_delta: number;
  cat_hp_after: number;
  leveled_up: boolean;
  tx_hash?: string;
}

// Appearance data matching the on-chain bit-packed felt252
interface AppearanceData {
  primaryR: number; primaryG: number; primaryB: number;
  stripeR: number; stripeG: number; stripeB: number;
  eyeR: number; eyeG: number; eyeB: number;
  headSize: number; eyeSize: number; eyeSpacing: number;
  bodyWidth: number; tailSize: number; hatId: number;
}

const HAT_NAMES = ["none", "chef_hat", "cowboy_hat", "crown", "pirate_hat", "viking_helmet", "winter_hat", "wizard_hat"];

function defaultAppearance(): AppearanceData {
  return {
    primaryR: 230, primaryG: 140, primaryB: 38,
    stripeR: 102, stripeG: 38, stripeB: 13,
    eyeR: 77, eyeG: 179, eyeB: 51,
    headSize: 8, eyeSize: 8, eyeSpacing: 8,
    bodyWidth: 8, tailSize: 8, hatId: 0,
  };
}

function randomAppearance(): AppearanceData {
  const r8 = () => Math.floor(Math.random() * 256);
  const r4 = () => Math.floor(Math.random() * 16);
  return {
    primaryR: r8(), primaryG: r8(), primaryB: r8(),
    stripeR: r8(), stripeG: r8(), stripeB: r8(),
    eyeR: r8(), eyeG: r8(), eyeB: r8(),
    headSize: r4(), eyeSize: r4(), eyeSpacing: r4(),
    bodyWidth: r4(), tailSize: r4(), hatId: 0,
  };
}

function packAppearance(d: AppearanceData): bigint {
  return BigInt(d.primaryR)
    + BigInt(d.primaryG) * (1n << 8n)
    + BigInt(d.primaryB) * (1n << 16n)
    + BigInt(d.stripeR) * (1n << 24n)
    + BigInt(d.stripeG) * (1n << 32n)
    + BigInt(d.stripeB) * (1n << 40n)
    + BigInt(d.eyeR) * (1n << 48n)
    + BigInt(d.eyeG) * (1n << 56n)
    + BigInt(d.eyeB) * (1n << 64n)
    + BigInt(d.headSize) * (1n << 72n)
    + BigInt(d.eyeSize) * (1n << 76n)
    + BigInt(d.eyeSpacing) * (1n << 80n)
    + BigInt(d.bodyWidth) * (1n << 84n)
    + BigInt(d.tailSize) * (1n << 88n)
    + BigInt(d.hatId) * (1n << 92n);
}

function unpackAppearance(packed: bigint): AppearanceData {
  const u8 = (shift: bigint) => Number((packed >> shift) & 0xFFn);
  const u4 = (shift: bigint) => Number((packed >> shift) & 0xFn);
  return {
    primaryR: u8(0n), primaryG: u8(8n), primaryB: u8(16n),
    stripeR: u8(24n), stripeG: u8(32n), stripeB: u8(40n),
    eyeR: u8(48n), eyeG: u8(56n), eyeB: u8(64n),
    headSize: u4(72n), eyeSize: u4(76n), eyeSpacing: u4(80n),
    bodyWidth: u4(84n), tailSize: u4(88n), hatId: u4(92n),
  };
}

function rgbToHex(r: number, g: number, b: number): string {
  return "#" + [r, g, b].map(c => c.toString(16).padStart(2, "0")).join("");
}

function hexToRgb(hex: string): [number, number, number] {
  const v = parseInt(hex.slice(1), 16);
  return [(v >> 16) & 255, (v >> 8) & 255, v & 255];
}

// Convert 0-15 bone scale to 0-1 float for the viewer
function boneToFloat(v: number): number { return v / 15; }

function appearanceToViewerConfig(d: AppearanceData) {
  return {
    primaryColor: rgbToHex(d.primaryR, d.primaryG, d.primaryB),
    stripeColor: rgbToHex(d.stripeR, d.stripeG, d.stripeB),
    eyeColor: rgbToHex(d.eyeR, d.eyeG, d.eyeB),
    headSize: boneToFloat(d.headSize),
    eyeSize: boneToFloat(d.eyeSize),
    bodyWidth: boneToFloat(d.bodyWidth),
    tailSize: boneToFloat(d.tailSize),
    hat: HAT_NAMES[d.hatId] ?? "none",
  };
}

function parseCat(r: any[]): CatState {
  const n = (i: number) => Number(BigInt(r[i]));
  return {
    id: n(0), owner: r[1], hp: n(3), max_hp: n(4),
    level: n(5), xp: n(6), attack: n(7), defense: n(8),
    speed: n(9), luck: n(10), alive: !!n(11),
    runs_completed: n(12), runs_failed: n(13),
  };
}

function parseRun(r: any[]): RunState {
  const n = (i: number) => Number(BigInt(r[i]));
  return {
    id: n(0), cat_id: n(1), current_node_id: n(3),
    node_count: n(4), status: n(5),
    score: n(6), nodes_visited: n(7),
  };
}

function felt252ToString(felt: string): string {
  const hex = BigInt(felt).toString(16);
  let s = "";
  for (let i = 0; i < hex.length; i += 2) {
    const code = parseInt(hex.substring(i, i + 2), 16);
    if (code > 0) s += String.fromCharCode(code);
  }
  return s;
}

function parseNode(r: any[]): NodeState {
  const n = (i: number) => Number(BigInt(r[i]));
  return {
    node_id: n(1), column: n(2), row: n(3), node_type: n(4),
    resolved: !!n(5), connections: n(10),
    skill_tag_1: felt252ToString(r[7]), skill_tag_2: felt252ToString(r[8]),
    difficulty: n(9),
  };
}

function hasConnection(connections: number, targetNodeId: number): boolean {
  return (connections & (1 << targetNodeId)) !== 0;
}

const rpcProvider = new RpcProvider({ nodeUrl: RPC_URL });

function delay(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

type Tab = "cats" | "catacombs" | "player";

function App() {
  const { client } = useDojoSDK();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();
  const { account, address } = useAccount();
  const [tab, setTab] = useState<Tab>("catacombs");
  const [autoConnecting, setAutoConnecting] = useState(
    () => !!localStorage.getItem("lastUsedConnector")
  );

  useEffect(() => {
    if (address || !localStorage.getItem("lastUsedConnector")) {
      setAutoConnecting(false);
    }
  }, [address]);

  useEffect(() => {
    if (!autoConnecting) return;
    const timer = setTimeout(() => setAutoConnecting(false), 3000);
    return () => clearTimeout(timer);
  }, [autoConnecting]);

  const [pending, setPending] = useState(false);
  const [creating, setCreating] = useState(false);
  const [appearance, setAppearance] = useState<AppearanceData>(defaultAppearance);
  const [shinies, setShinies] = useState<number>(0);
  const [strkBalance, setStrkBalance] = useState<string>("0");
  const [cats, setCats] = useState<{ cat: CatState; appearance: AppearanceData | null }[]>([]);
  const [selectedCatId, setSelectedCatId] = useState<number | null>(null);
  const [connectDance] = useState(() => pickRandom(DANCE_ANIMS));
  const [catIdleAnim, setCatIdleAnim] = useState(IDLE_ANIM);
  const [run, setRun] = useState<RunState | null>(null);
  const [nodes, setNodes] = useState<NodeState[]>([]);
  const [runLog, setRunLog] = useState<RunLogEntry[]>([]);
  const [toasts, setToasts] = useState<Toast[]>([]);
  const [defeat, setDefeat] = useState<{ score: number; nodesVisited: number; status: string } | null>(null);
  const txIdRef = useRef(1);

  const selectedEntry = cats.find(e => e.cat.id === selectedCatId);
  const cat = selectedEntry?.cat ?? null;
  const catAppearance = selectedEntry?.appearance ?? null;

  // The cat actually on the active run (for stats bar on Catacombs tab)
  const runCatEntry = (run && run.status === 0) ? cats.find(e => e.cat.id === run.cat_id) : null;
  const runCat = runCatEntry?.cat ?? null;

  // Use refs for latest state to avoid stale closures in callbacks
  const catRef = useRef(cat);
  const runRef = useRef(run);
  useEffect(() => { catRef.current = cat; }, [cat]);
  useEffect(() => { runRef.current = run; }, [run]);

  const fetchCat = useCallback(async (catId: number) => {
    try {
      const result = await client.cat_actions.get_cat(catId);
      const parsed = parseCat(result);
      if (result && parsed.max_hp > 0) {
        let app: AppearanceData | null = null;
        try {
          const appResult = await client.cat_actions.get_cat_appearance(catId);
          const packed = BigInt(appResult[1]);
          if (packed > 0n) app = unpackAppearance(packed);
        } catch { /* appearance may not exist for old cats */ }
        setCats(prev => {
          const without = prev.filter(e => e.cat.id !== catId);
          return [...without, { cat: parsed, appearance: app }].sort((a, b) => a.cat.id - b.cat.id);
        });
        return parsed;
      }
    } catch { /* cat doesn't exist */ }
    return null;
  }, [client]);

  const fetchAllCats = useCallback(async () => {
    const found: { cat: CatState; appearance: AppearanceData | null }[] = [];
    for (let id = 1; id <= 20; id++) {
      try {
        const result = await client.cat_actions.get_cat(id);
        const parsed = parseCat(result);
        if (parsed.max_hp > 0) {
          let app: AppearanceData | null = null;
          try {
            const appResult = await client.cat_actions.get_cat_appearance(id);
            const packed = BigInt(appResult[1]);
            if (packed > 0n) app = unpackAppearance(packed);
          } catch {}
          found.push({ cat: parsed, appearance: app });
        }
      } catch { continue; }
    }
    setCats(found);
    if (found.length > 0) {
      setSelectedCatId(prev => prev ?? found[0].cat.id);
    }
  }, [client]);

  const fetchShinies = useCallback(async () => {
    if (!address) return;
    try {
      const result = await client.shiny_actions.get_balance(address);
      setShinies(Number(BigInt(result[0])));
    } catch { /* no balance yet */ }
    try {
      const result = await client.shiny_actions.get_strk_balance(address);
      // STRK has 18 decimals, show as human-readable
      const raw = BigInt(result[0]) + (BigInt(result[1]) << 128n);
      const whole = raw / 1_000_000_000_000_000_000n;
      const frac = (raw % 1_000_000_000_000_000_000n) / 1_000_000_000_000_000n; // 3 decimal places
      setStrkBalance(`${whole}.${frac.toString().padStart(3, "0")}`);
    } catch { /* no strk balance */ }
  }, [address, client]);

  const fetchRun = useCallback(async (runId: number) => {
    try {
      const result = await client.run_actions.get_run(runId);
      if (result && Number(BigInt(result[0])) > 0) {
        const r = parseRun(result);
        setRun(r);
        // Fetch all nodes: IDs 0, then 1..((node_count-2)*1), then 25 (boss)
        // Node IDs: 0 (start), 1..(node_count-2) for middle, 25 (boss)
        const nodeIds: number[] = [];
        for (let i = 0; i < r.node_count; i++) {
          // We don't know exact IDs, but they're: 0, 1..N, 25
          // Middle nodes use (col-1)*3+1+row, max ID is 25
          // Safest: fetch all possible IDs 0-25
          nodeIds.push(i);
        }
        // Fetch all possible node IDs 0 through 19 and filter out empty ones
        const allIds = Array.from({ length: 20 }, (_, i) => i);
        const nodeResults = await Promise.all(
          allIds.map(id => client.run_actions.get_node(runId, id).catch(() => null))
        );
        const parsed: NodeState[] = [];
        for (const nr of nodeResults) {
          if (nr) {
            const node = parseNode(nr);
            // Filter out uninitialized nodes (column=0 and row=0 and node_type=0 and node_id != 0)
            if (node.node_id === 0 || node.column > 0 || node.node_type > 0) {
              parsed.push(node);
            }
          }
        }
        setNodes(parsed);
      } else {
        setRun(null);
        setNodes([]);
      }
    } catch { setRun(null); setNodes([]); }
  }, [client]);

  const addToast = useCallback((message: string, type: "success" | "error" | "info" = "info") => {
    const id = txIdRef.current++;
    setToasts(prev => [...prev, { id, message, type, timestamp: Date.now() }]);
    setTimeout(() => setToasts(prev => prev.filter(t => t.id !== id)), 4000);
  }, []);

  // Poll an RPC read until a condition is met (retries up to maxAttempts)
  const pollUntil = useCallback(async <T,>(
    read: () => Promise<T>,
    condition: (result: T) => boolean,
    maxAttempts = 10,
    intervalMs = 1000,
  ): Promise<T | null> => {
    for (let i = 0; i < maxAttempts; i++) {
      try {
        const result = await read();
        if (condition(result)) return result;
      } catch { /* keep polling */ }
      await delay(intervalMs);
    }
    return null;
  }, []);

  // Core transaction wrapper: executes fn, waits for tx, then runs onConfirmed callback
  const wrap = useCallback(
    async (fn: () => Promise<any>, actionName: string, onConfirmed?: (txHash?: string) => Promise<void>) => {
      if (!account) return;
      setPending(true);
      try {
        const result = await fn();
        const txHash = result?.transaction_hash;
        if (txHash) {
          addToast(`${actionName}...`, "info");
          await rpcProvider.waitForTransaction(txHash, { retryInterval: 500 });
        }
        if (onConfirmed) {
          await onConfirmed(txHash);
        }
        addToast(actionName, "success");
      } catch (e: any) {
        addToast(e.message?.slice(0, 80) ?? String(e).slice(0, 80), "error");
      } finally {
        setPending(false);
      }
    },
    [account, addToast]
  );

  const createCat = (app: AppearanceData) =>
    wrap(
      () => client.cat_actions.create_cat(account!, "12345", "0x" + packAppearance(app).toString(16)),
      "Create Cat",
      async () => {
        // Find the newly created cat by scanning IDs
        const startId = cats.length > 0 ? Math.max(...cats.map(e => e.cat.id)) + 1 : 1;
        const found = await pollUntil(
          async () => {
            for (let id = startId; id < startId + 10; id++) {
              try {
                const r = await client.cat_actions.get_cat(id);
                if (parseCat(r).max_hp > 0) return id;
              } catch { continue; }
            }
            return -1;
          },
          (id) => id > 0,
        );
        if (found && found > 0) {
          await fetchCat(found);
          setSelectedCatId(found);
        }
        setCreating(false);
        fetchShinies();
      },
    );

  const buyShinies = (amount: number) =>
    wrap(
      () => client.shiny_actions.buy_shinies(account!, amount),
      `Buy ${amount} SHINIES`,
      async () => {
        fetchShinies();
      },
    );

  const startRun = () => {
    if (!catRef.current) { addToast("Select a cat first", "error"); return; }
    const runCatId = catRef.current.id;
    return wrap(
      () => client.run_actions.start_run(account!, runCatId),
      "Start Run",
      async () => {
        // Poll for the new active run by scanning IDs
        const startId = (runRef.current?.id ?? 0) + 1;
        const found = await pollUntil(
          async () => {
            for (let id = startId; id < startId + 10; id++) {
              try {
                const r2 = await client.run_actions.get_run(id);
                const r = parseRun(r2);
                if (r.cat_id === runCatId && r.status === 0) return id;
              } catch { continue; }
            }
            return -1;
          },
          (id) => id > 0,
        );
        if (found && found > 0) {
          setRunLog([]);
          setDefeat(null);
          await fetchRun(found);
          // EGS: mint game token and bind it to this run in one call (Sepolia/Mainnet only)
          if (CHAIN === "sepolia" || CHAIN === "mainnet") {
            try {
              addToast("Minting EGS token...", "info");
              const egsResult = await client.egs_adapter.mint_and_register(account!, address!, found);
              if (egsResult?.transaction_hash) {
                await rpcProvider.waitForTransaction(egsResult.transaction_hash, { retryInterval: 500 });
                addToast("EGS token linked", "success");
              }
            } catch (e: any) {
              // Non-fatal: run works fine without EGS binding
              addToast("EGS: " + (e.message?.slice(0, 60) ?? String(e).slice(0, 60)), "info");
            }
          }
        }
      },
    );
  };

  const choosePath = (nodeId: number) => {
    // Find the target node to describe what we're heading into
    const targetNode = nodes.find(n => n.node_id === nodeId);
    const targetType = targetNode ? NODE_TYPES[targetNode.node_type] : "?";
    const isSkillCheck = targetType === "Combat" || targetType === "Event";
    const skillDesc = targetNode?.skill_tag_1
      ? `${targetNode.skill_tag_1}${targetNode.skill_tag_2 ? ` + ${targetNode.skill_tag_2}` : ""}`
      : "";
    const label = isSkillCheck
      ? `Move \u2192 ${skillDesc} check`
      : `Move \u2192 ${targetType}`;

    return wrap(
      () => {
        const r = runRef.current;
        if (!r) return Promise.resolve();
        return client.run_actions.choose_path(account!, r.id, nodeId);
      },
      label,
      async (txHash?: string) => {
        const r = runRef.current;
        if (!r) return;
        // Poll until node changes or run ends
        const finalRunResult = await pollUntil(
          () => client.run_actions.get_run(r.id),
          (result) => {
            try {
              const parsed = parseRun(result);
              return parsed.current_node_id === nodeId || parsed.status !== 0;
            }
            catch { return false; }
          },
        );
        await fetchRun(r.id);
        // Check if run ended
        const finalRun = finalRunResult ? parseRun(finalRunResult) : null;
        const runEnded = finalRun && finalRun.status !== 0;
        // Read resolution outcome and add to run log
        try {
          const outcome = await client.run_actions.get_node_outcome(r.id, nodeId);
          // Fields: [0]=run_id, [1]=node_id, [2]=skill_tag, [3]=cat_stat, [4]=roll,
          // [5]=difficulty, [6]=result, [7]=hp_delta, [8]=xp_gained, [9]=score_delta,
          // [10]=cat_hp_after, [11]=cat_xp_after, [12]=leveled_up
          const b = (i: number) => BigInt(outcome[i]);
          const n = (i: number) => Number(b(i));
          const resultCode = n(6);
          // hp_delta is i8 in Cairo — negative values are stored as felt252 (prime - abs)
          const FELT_PRIME = 2n ** 251n + 17n * 2n ** 192n + 1n;
          const rawHpBig = b(7);
          const hpDelta = rawHpBig > FELT_PRIME / 2n
            ? Number(rawHpBig - FELT_PRIME)  // negative
            : Number(rawHpBig);              // positive or zero
          const entry: RunLogEntry = {
            node_id: nodeId,
            node_type: targetType,
            skill_tag: felt252ToString(outcome[2]),
            cat_stat: n(3),
            roll: n(4),
            difficulty: n(5),
            result: resultCode === 1 ? "success" : resultCode === 2 ? "partial" : resultCode === 3 ? "failure" : "n/a",
            hp_delta: hpDelta,
            xp_gained: n(8),
            score_delta: n(9),
            cat_hp_after: n(10),
            leveled_up: !!n(12),
            tx_hash: txHash,
          };
          setRunLog(prev => [...prev, entry]);
          // Show result toast
          if (resultCode >= 1 && resultCode <= 3) {
            const tag = ["", "Success", "Partial", "Failure"][resultCode];
            const hpStr = hpDelta > 0 ? `+${hpDelta}` : `${hpDelta}`;
            addToast(`${tag}: ${hpStr} HP, +${entry.xp_gained} XP${entry.leveled_up ? " \u2191 LEVEL UP!" : ""}`, resultCode === 1 ? "success" : resultCode === 3 ? "error" : "info");
          }
          // Refresh cat stats after resolution
          if (catRef.current) await fetchCat(catRef.current.id);
        } catch { /* outcome read failed, non-fatal */ }
        // Show defeat/victory screen if run ended
        if (runEnded && finalRun) {
          setDefeat({
            score: finalRun.score,
            nodesVisited: finalRun.nodes_visited,
            status: RUN_STATUS[finalRun.status] ?? "Failed",
          });
        }
      },
    );
  };

  const abandonRun = () =>
    wrap(
      () => {
        const r = runRef.current;
        if (!r) return Promise.resolve();
        return client.run_actions.abandon_run(account!, r.id);
      },
      "Abandon Run",
      async () => {
        const r = runRef.current;
        if (r) {
          // Poll until run status changes from Active (0)
          const finalResult = await pollUntil(
            () => client.run_actions.get_run(r.id),
            (result) => {
              try { return parseRun(result).status !== 0; }
              catch { return false; }
            },
          );
          await fetchRun(r.id);
          const finalRun = finalResult ? parseRun(finalResult) : null;
          setDefeat({
            score: finalRun?.score ?? r.score ?? 0,
            nodesVisited: finalRun?.nodes_visited ?? r.nodes_visited ?? 0,
            status: "Failed",
          });
        }
        if (catRef.current) await fetchCat(catRef.current.id);
      },
    );

  // Auto-fetch on connect
  useEffect(() => {
    if (!address || !client) return;
    fetchAllCats();
    fetchShinies();
    (async () => {
      for (let id = 10; id >= 1; id--) {
        try {
          const result = await client.run_actions.get_run(id);
          const r = parseRun(result);
          if (r.cat_id > 0 && r.status === 0) {
            await fetchRun(id);
            setSelectedCatId(r.cat_id);
            return;
          }
        } catch { continue; }
      }
      for (let id = 10; id >= 1; id--) {
        try {
          const result = await client.run_actions.get_run(id);
          const r = parseRun(result);
          if (r.cat_id > 0) {
            setRun(r);
            return;
          }
        } catch { continue; }
      }
    })();
  }, [address, client, fetchAllCats, fetchRun, fetchShinies]);

  const connected = !!address;
  const currentNode = nodes.find(n => n.node_id === run?.current_node_id);
  const currentNodeType = currentNode ? NODE_TYPES[currentNode.node_type] : undefined;
  const catAnimation = connected
    ? (tab === "cats" ? catIdleAnim
      : defeat ? (defeat.status === "Completed" ? VICTORY_ANIM : DEFEAT_ANIM)
      : getCatAnimation(run, currentNodeType, pending))
    : connectDance;
  const catScene = connected
    ? (defeat ? "cozy_fireplace" : getCatScene(currentNodeType))
    : "default_studio";
  const viewerSlotClass = connected ? `cat-viewer-slot slot-${tab}` : "cat-viewer-slot slot-connect";

  // Show the cat's on-chain appearance in the viewer (creator overrides when active)
  // On Catacombs tab, show the running cat; on Cats tab, show the selected/browsed cat
  const viewerCatAppearance = (tab === "catacombs" && runCatEntry)
    ? runCatEntry.appearance
    : catAppearance;
  const activeAppearance = (tab === "cats" && creating)
    ? appearance
    : viewerCatAppearance ?? defaultAppearance();
  // Memoize so the reference only changes when actual values change or cat selection changes
  const viewerAppearance = useMemo(
    () => appearanceToViewerConfig(activeAppearance),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [selectedCatId, tab, run?.cat_id, creating, JSON.stringify(activeAppearance)]
  );

  return (
    <div className={connected ? "app" : "connect-screen"}>
      {/* Always-mounted cat viewer — never unmounts across screens or tabs */}
      <div className={viewerSlotClass}>
        <CatViewer
          animation={catAnimation}
          scene={catScene}
          autoRotate={!connected}
          appearance={viewerAppearance}
          camera={!connected ? { distance: 1.24, yaw: 4.2, pitch: -1.4 } : undefined}
          cameraTarget={!connected ? { x: 0, y: 0.264, z: 0 } : undefined}
        />
      </div>

      {/* ===== CONNECT SCREEN ===== */}
      {!connected && (
        <div className="connect-card">
          <h1 className="connect-title">Catacombs</h1>
          <p className="connect-subtitle">A cat-like rogue-like</p>
          <div className="connect-divider" />
          {autoConnecting ? (
            <p className="connect-status">Connecting...</p>
          ) : (
            <button
              className="connect-btn"
              onClick={() => connect({ connector: connectors[0] })}
            >
              Start Playing
            </button>
          )}
        </div>
      )}

      {/* Toasts */}
      {toasts.length > 0 && (
        <div className="toast-container">
          {toasts.map(t => (
            <div key={t.id} className={`toast toast-${t.type}`}>
              {t.type === "success" ? "\u2713" : t.type === "error" ? "\u2717" : "\u2022"} {t.message}
            </div>
          ))}
        </div>
      )}

      {/* ===== CATS TAB ===== */}
      {connected && tab === "cats" && (
        <div className="tab-content">
          {/* SHINIES Balance */}
          <div className="shinies-bar">
            <span className="shinies-label">SHINIES</span>
            <span className="shinies-value">{shinies}</span>
            {shinies < 10 && (
              <button className="btn btn-primary btn-sm" onClick={() => buyShinies(10)} disabled={pending}>
                Buy 10 (10 STRK)
              </button>
            )}
          </div>

          {creating ? (
            <CatCreator
              appearance={appearance}
              onChange={setAppearance}
              onConfirm={() => shinies >= 10 ? createCat(appearance) : addToast("Need 10 SHINIES to summon a cat", "error")}
              onCancel={() => setCreating(false)}
              pending={pending}
            />
          ) : (
            <>
              {/* Cat Roster */}
              {cats.length > 0 && (
                <div className="cat-roster">
                  {cats.map(entry => {
                    const isRunning = run && run.status === 0 && run.cat_id === entry.cat.id;
                    return (
                    <button
                      key={entry.cat.id}
                      className={`roster-item ${entry.cat.id === selectedCatId ? "selected" : ""} ${isRunning ? "in-run" : ""}`}
                      onClick={() => {
                        setSelectedCatId(entry.cat.id);
                        setCatIdleAnim(prev => pickRandom(IDLE_ANIMS, prev));
                      }}
                    >
                      <span className="roster-id">#{entry.cat.id}</span>
                      <span className="roster-level">Lv.{entry.cat.level}</span>
                      {isRunning ? (
                        <span className="roster-status in-run">{"\u2302"}</span>
                      ) : (
                        <span className={`roster-status ${entry.cat.alive ? "" : "wounded"}`}>
                          {entry.cat.alive ? "\u2665" : "\u2620"}
                        </span>
                      )}
                    </button>
                    );
                  })}
                  <button className="roster-item roster-add" onClick={() => setCreating(true)}>
                    <span className="roster-plus">+</span>
                  </button>
                </div>
              )}

              {/* Selected Cat Details */}
              {cat ? (
                <div className="card">
                  <h3 className="card-title">Cat #{cat.id}</h3>
                  <div className="stats-grid">
                    <StatCell label="Level" value={cat.level} accent />
                    <StatCell label="XP" value={cat.xp} />
                    <StatCell label="HP" value={`${cat.hp}/${cat.max_hp}`}
                      hpLevel={cat.hp / cat.max_hp} />
                    <StatCell label="ATK" value={cat.attack} />
                    <StatCell label="DEF" value={cat.defense} />
                    <StatCell label="SPD" value={cat.speed} />
                    <StatCell label="LCK" value={cat.luck} />
                    <StatCell label="Status" value={cat.alive ? "Alive" : "Wounded"}
                      hpLevel={cat.alive ? 1 : 0} />
                  </div>
                  <div className="hp-bar-container">
                    <div className="hp-bar-track">
                      <div
                        className={`hp-bar-fill ${
                          cat.hp / cat.max_hp > 0.66 ? 'high' :
                          cat.hp / cat.max_hp > 0.33 ? 'mid' : 'low'
                        }`}
                        style={{ width: `${(cat.hp / cat.max_hp) * 100}%` }}
                      />
                    </div>
                  </div>
                  <div className="runs-meta">
                    {cat.runs_completed} completed / {cat.runs_failed} failed
                  </div>
                </div>
              ) : (
                <div className="card">
                  <h3 className="card-title">No Cats Yet</h3>
                  <div className="empty-state">
                    <p>Create your first cat to begin exploring the catacombs.</p>
                    <button className="btn btn-primary" onClick={() => setCreating(true)}>
                      Create Cat
                    </button>
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      )}

      {/* ===== CATACOMBS TAB ===== */}
      {connected && tab === "catacombs" && (
        <div className="tab-content">
          {run && run.status === 0 ? (
            <>
              {/* Compact cat stats bar */}
              {runCat && (
                <div className="cat-stats-bar">
                  <span className="cat-stats-name">Cat #{runCat.id}</span>
                  <span className="cat-stat"><span className="stat-icon hp">{"\u2665"}</span> {runCat.hp}/{runCat.max_hp}</span>
                  <span className="cat-stat"><span className="stat-icon atk">{"\u2694"}</span>{runCat.attack}</span>
                  <span className="cat-stat"><span className="stat-icon def">{"\u25C6"}</span>{runCat.defense}</span>
                  <span className="cat-stat"><span className="stat-icon spd">{"\u2192"}</span>{runCat.speed}</span>
                  <span className="cat-stat"><span className="stat-icon lck">{"\u2618"}</span>{runCat.luck}</span>
                  <button className="btn-abandon" onClick={abandonRun} disabled={pending}>Flee</button>
                </div>
              )}

              {/* Map */}
              <MapView
                run={run}
                nodes={nodes}
                currentConnections={currentNode?.connections ?? 0}
                onChoosePath={choosePath}
                pending={pending}
              />

              {/* Run History */}
              {runLog.length > 0 && (
                <RunHistory entries={runLog} explorerUrl={EXPLORER_URL} />
              )}
            </>
          ) : defeat ? (
            /* Defeat / Victory overlay */
            <div className={`run-end-screen ${defeat.status === "Completed" ? "victory" : "defeat"}`}>
              <div className="run-end-vignette" />
              <div className="run-end-content">
                <h2 className="run-end-title">
                  {defeat.status === "Completed" ? "Victory" : "Defeated"}
                </h2>
                <div className="run-end-divider" />
                <div className="run-end-stats">
                  <div className="run-end-stat">
                    <span className="run-end-stat-value">{defeat.score}</span>
                    <span className="run-end-stat-label">Score</span>
                  </div>
                  <div className="run-end-stat">
                    <span className="run-end-stat-value">{defeat.nodesVisited}</span>
                    <span className="run-end-stat-label">Nodes</span>
                  </div>
                </div>
                {runLog.length > 0 && (
                  <RunHistory entries={runLog} explorerUrl={EXPLORER_URL} />
                )}
                <button className="btn btn-primary run-end-btn" onClick={() => setDefeat(null)}>
                  Continue
                </button>
              </div>
            </div>
          ) : (
            <div className="card">
              <h3 className="card-title">Run</h3>
              <div className="empty-state">
                <p>
                  {run ? `Last run: ${RUN_STATUS[run.status]}` : "No active run"}
                </p>
                {cat ? (
                  <>
                    <p style={{ fontSize: 13, color: "var(--amber)", marginBottom: 8 }}>
                      Sending Cat #{cat.id} (Lv.{cat.level})
                    </p>
                    <button className="btn btn-primary" onClick={startRun}
                      disabled={pending || !cat.alive}>
                      Begin Descent
                    </button>
                    {!cat.alive && (
                      <p style={{ fontSize: 12, color: "var(--danger)", marginTop: 6 }}>
                        This cat is wounded and cannot run
                      </p>
                    )}
                  </>
                ) : (
                  <p style={{ fontSize: 12, color: "var(--stone-500)" }}>
                    Summon a cat first in the Cats tab
                  </p>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* ===== PLAYER TAB ===== */}
      {connected && tab === "player" && (
        <div className="tab-content">
          <div className="card">
            <h3 className="card-title">Player</h3>
            <div className="player-field">
              <span className="player-label">Wallet</span>
              <span
                className="player-value player-address"
                onClick={() => navigator.clipboard.writeText(address)}
                title="Click to copy"
              >
                {address}
              </span>
            </div>
            <div className="player-field">
              <span className="player-label">SHINIES</span>
              <span className="player-value">{shinies}</span>
            </div>
            <div className="player-field">
              <span className="player-label">STRK</span>
              <span className="player-value">{strkBalance}</span>
            </div>
            {cat && (
              <div className="player-field">
                <span className="player-label">Cat</span>
                <span className="player-value">#{cat.id} &middot; Level {cat.level}</span>
              </div>
            )}
            {run && (
              <div className="player-field">
                <span className="player-label">Last Run</span>
                <span className="player-value">#{run.id} &middot; {RUN_STATUS[run.status]}</span>
              </div>
            )}
            <div className="buy-shinies-row" style={{ marginTop: 16, display: "flex", gap: 8, flexWrap: "wrap" }}>
              {[10, 50, 100].map(amt => (
                <button key={amt} className="btn btn-primary" onClick={() => buyShinies(amt)} disabled={pending}>
                  Buy {amt} SHINIES ({amt} STRK)
                </button>
              ))}
            </div>
            <div style={{ marginTop: 20 }}>
              <button className="btn btn-danger" onClick={() => disconnect()}>
                Disconnect Wallet
              </button>
            </div>
          </div>

        </div>
      )}

      {/* Tab Bar */}
      {connected && (
        <nav className="tab-bar">
          <button
            className={`tab-btn ${tab === "cats" ? "active" : ""}`}
            onClick={() => setTab("cats")}
          >
            <span className="tab-icon">{"\u2666"}</span>
            <span className="tab-label">Cats</span>
          </button>
          <button
            className={`tab-btn ${tab === "catacombs" ? "active" : ""}`}
            onClick={() => setTab("catacombs")}
          >
            <span className="tab-icon">{"\u2302"}</span>
            <span className="tab-label">Catacombs</span>
          </button>
          <button
            className={`tab-btn ${tab === "player" ? "active" : ""}`}
            onClick={() => setTab("player")}
          >
            <span className="tab-icon">{"\u2605"}</span>
            <span className="tab-label">Player</span>
          </button>
        </nav>
      )}

      {/* Pending indicator */}
      {connected && pending && (
        <div className="pending-indicator">
          <div className="pending-dot" />
          Processing transaction...
        </div>
      )}
    </div>
  );
}

// ===== COMPONENTS =====

function StatCell({ label, value, hpLevel, accent }: {
  label: string;
  value: string | number;
  hpLevel?: number;
  accent?: boolean;
}) {
  let colorClass = "";
  if (hpLevel !== undefined) {
    colorClass = hpLevel > 0.66 ? "hp-high" : hpLevel > 0.33 ? "hp-mid" : "hp-low";
  } else if (accent) {
    colorClass = "accent";
  }
  return (
    <div className="stat">
      <div className="stat-label">{label}</div>
      <div className={`stat-value ${colorClass}`}>{value}</div>
    </div>
  );
}

const RESULT_LABELS: Record<string, string> = {
  success: "\u2713 Success", partial: "\u25CB Partial", failure: "\u2717 Failure", "n/a": "",
};
const RESULT_COLORS: Record<string, string> = {
  success: "var(--venom-400)", partial: "var(--amber)", failure: "var(--blood-400)", "n/a": "var(--stone-400)",
};

const SKILL_LABEL: Record<string, string> = {
  combat: "ATK", stealth: "SPD", agility: "SPD", charm: "LCK", arcane: "DEF", survival: "ATK",
};

function RunHistory({ entries, explorerUrl }: { entries: RunLogEntry[]; explorerUrl: string }) {
  const listRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    listRef.current?.scrollTo({ top: listRef.current.scrollHeight, behavior: "smooth" });
  }, [entries.length]);

  return (
    <div className="run-history">
      <h4 className="run-history-title">Run Log</h4>
      <div className="run-history-list" ref={listRef}>
        {entries.map((e, i) => {
          const icon = NODE_ICONS[e.node_type] ?? SKILL_ICONS[e.skill_tag] ?? "\u25C9";
          const hpStr = e.hp_delta > 0 ? `+${e.hp_delta}` : `${e.hp_delta}`;
          const isSkillCheck = e.result !== "n/a" && e.roll > 0;
          const isBoss = e.node_type === "Boss";
          const threshold = isBoss ? 18 : e.difficulty * 4 + 4;
          return (
            <div key={i} className={`run-log-entry result-${e.result}`}>
              <div className="log-header">
                <span className="log-icon">{icon}</span>
                <span className="log-node-type">{e.node_type}</span>
                {isSkillCheck && (
                  <span className="log-check">
                    {e.skill_tag ? `${e.skill_tag} (${SKILL_LABEL[e.skill_tag] ?? "?"} ${e.cat_stat})` : ""} d20:{e.roll} vs {threshold}
                  </span>
                )}
                <span className="log-result" style={{ color: RESULT_COLORS[e.result] }}>
                  {RESULT_LABELS[e.result]}
                </span>
              </div>
              <div className="log-effects">
                <span className={`log-hp ${e.hp_delta >= 0 ? "heal" : "damage"}`}>{hpStr} HP</span>
                <span className="log-xp">+{e.xp_gained} XP</span>
                {e.score_delta > 0 && <span className="log-score">+{e.score_delta} pts</span>}
                {e.leveled_up && <span className="log-levelup">{"\u2191"} LEVEL UP!</span>}
                <span className="log-hp-after">{e.cat_hp_after} HP left</span>
                {explorerUrl && e.tx_hash && (
                  <a className="log-tx" href={`${explorerUrl}/tx/${e.tx_hash}`} target="_blank" rel="noopener">tx</a>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// Animation mapping: node type -> cat animation
const NODE_ANIM: Record<string, string> = {
  Start: "Idle_Dreamer",
  Combat: "Sword_Attack_Light",
  Treasure: "Cat_Robot_Hip_Hop_Dance",
  Rest: "Cat_Seated_Idle",
  Event: "Cat_Looking_Around",
  Shop: "Cat_Waving",
  Boss: "Sword_Attack_Medium",
};

const PENDING_ANIM = "Cat_Walking_Backwards";
const DEFEAT_ANIM = "Sword_Death";
const VICTORY_ANIM = "Cat_Robot_Hip_Hop_Dance";
const IDLE_ANIM = "Idle_Dreamer";

const DANCE_ANIMS = ["Cat_Macarena_Dance", "Cat_Robot_Hip_Hop_Dance", "Cat_Salsa_Dancing"];
const IDLE_ANIMS = ["Idle_Dreamer", "Idle_Harmonic", "Idle_Invasive", "Cat_Looking_Around", "Cat_Seated_Idle"];

function pickRandom<T>(arr: T[], exclude?: T): T {
  const filtered = exclude ? arr.filter(a => a !== exclude) : arr;
  return filtered[Math.floor(Math.random() * filtered.length)];
}

function getCatAnimation(
  run: RunState | null,
  currentNodeType: string | undefined,
  pending: boolean,
): string {
  if (pending) return PENDING_ANIM;
  if (!run || run.status !== 0) return IDLE_ANIM;
  if (currentNodeType) return NODE_ANIM[currentNodeType] ?? IDLE_ANIM;
  return IDLE_ANIM;
}

function getCatScene(currentNodeType: string | undefined): string {
  switch (currentNodeType) {
    case "Combat": case "Boss": return "neon_city";
    case "Treasure": return "cozy_fireplace";
    case "Rest": return "moonlit_garden";
    case "Event": return "sakura_garden";
    case "Shop": return "winter_wonderland";
    default: return "default_studio";
  }
}

function CatViewer({ animation, scene, autoRotate = false, appearance, camera, cameraTarget }: {
  animation: string;
  scene: string;
  autoRotate?: boolean;
  appearance?: Record<string, any> | null;
  camera?: { distance: number; yaw: number; pitch: number };
  cameraTarget?: { x: number; y: number; z: number };
}) {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const prevProps = useRef({ animation: "", scene: "", autoRotate: false, appearance: "" });
  const iframeReady = useRef(false);

  // Listen for ready signal from iframe (Godot finished loading)
  useEffect(() => {
    const onMessage = (e: MessageEvent) => {
      if (e.data?.type === "catViewer:ready") {
        iframeReady.current = true;
        // Re-send full config now that Godot is ready
        const iframe = iframeRef.current;
        if (!iframe?.contentWindow) return;
        const config: Record<string, any> = { animation, scene, autoRotate };
        if (appearance) Object.assign(config, appearance);
        if (camera) config.camera = camera;
        if (cameraTarget) config.cameraTarget = cameraTarget;
        iframe.contentWindow.postMessage({ type: "catViewer:configure", config }, "*");
      }
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [animation, scene, autoRotate, appearance, camera, cameraTarget]);

  // Send configure messages when props change
  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe?.contentWindow) return;

    const config: Record<string, any> = {};
    if (animation !== prevProps.current.animation) config.animation = animation;
    if (scene !== prevProps.current.scene) config.scene = scene;
    if (autoRotate !== prevProps.current.autoRotate) config.autoRotate = autoRotate;

    prevProps.current = { ...prevProps.current, animation, scene, autoRotate };

    if (camera) config.camera = camera;
    if (cameraTarget) config.cameraTarget = cameraTarget;

    if (Object.keys(config).length > 0) {
      iframe.contentWindow.postMessage(
        { type: "catViewer:configure", config },
        "*"
      );
    }
  }, [animation, scene, autoRotate, camera, cameraTarget]);

  // Send appearance separately — always resend when appearance changes
  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe?.contentWindow || !appearance) return;

    iframe.contentWindow.postMessage(
      { type: "catViewer:configure", config: appearance },
      "*"
    );
  }, [appearance]);

  const src = useMemo(
    () => `${CAT_VIEWER_BASE}/embed.html?scene=${encodeURIComponent(scene)}&animation=${encodeURIComponent(animation)}&autoRotate=${autoRotate}&camDist=1.24&camY=4.2&camX=-1.4&camTargetY=0.264`,
    // Only set src once on mount — subsequent changes use postMessage
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );

  return (
    <iframe
      ref={iframeRef}
      src={src}
      className="cat-viewer-panel"
      allow="autoplay"
    />
  );
}

function CatCreator({ appearance, onChange, onConfirm, onCancel, pending }: {
  appearance: AppearanceData;
  onChange: (a: AppearanceData) => void;
  onConfirm: () => void;
  onCancel: () => void;
  pending: boolean;
}) {
  const set = (field: keyof AppearanceData, value: number) =>
    onChange({ ...appearance, [field]: value });

  const setColor = (prefix: "primary" | "stripe" | "eye", hex: string) => {
    const [r, g, b] = hexToRgb(hex);
    onChange({
      ...appearance,
      [`${prefix}R`]: r,
      [`${prefix}G`]: g,
      [`${prefix}B`]: b,
    } as any);
  };

  return (
    <div className="card">
      <h3 className="card-title">Create Your Cat</h3>

      <div className="creator-section">
        <label className="creator-label">Fur Color</label>
        <input type="color" className="creator-color"
          value={rgbToHex(appearance.primaryR, appearance.primaryG, appearance.primaryB)}
          onChange={e => setColor("primary", e.target.value)} />
      </div>

      <div className="creator-section">
        <label className="creator-label">Stripe Color</label>
        <input type="color" className="creator-color"
          value={rgbToHex(appearance.stripeR, appearance.stripeG, appearance.stripeB)}
          onChange={e => setColor("stripe", e.target.value)} />
      </div>

      <div className="creator-section">
        <label className="creator-label">Eye Color</label>
        <input type="color" className="creator-color"
          value={rgbToHex(appearance.eyeR, appearance.eyeG, appearance.eyeB)}
          onChange={e => setColor("eye", e.target.value)} />
      </div>

      <div className="creator-section">
        <label className="creator-label">Head Size</label>
        <input type="range" className="creator-slider" min={0} max={15} step={1}
          value={appearance.headSize} onChange={e => set("headSize", +e.target.value)} />
      </div>

      <div className="creator-section">
        <label className="creator-label">Eye Size</label>
        <input type="range" className="creator-slider" min={0} max={15} step={1}
          value={appearance.eyeSize} onChange={e => set("eyeSize", +e.target.value)} />
      </div>

      <div className="creator-section">
        <label className="creator-label">Body Width</label>
        <input type="range" className="creator-slider" min={0} max={15} step={1}
          value={appearance.bodyWidth} onChange={e => set("bodyWidth", +e.target.value)} />
      </div>

      <div className="creator-section">
        <label className="creator-label">Tail Size</label>
        <input type="range" className="creator-slider" min={0} max={15} step={1}
          value={appearance.tailSize} onChange={e => set("tailSize", +e.target.value)} />
      </div>

      <div className="creator-buttons">
        <button className="btn btn-secondary" onClick={() => onChange(randomAppearance())} disabled={pending}>
          Randomize
        </button>
        <button className="btn btn-primary" onClick={onConfirm} disabled={pending}>
          {pending ? "Creating..." : "Summon Cat"}
        </button>
        <button className="btn btn-danger" onClick={onCancel} disabled={pending}>
          Cancel
        </button>
      </div>
    </div>
  );
}

// Difficulty shown as dots: · ·· ···
const DIFF_DOTS = ["", "\u00B7", "\u00B7\u00B7", "\u00B7\u00B7\u00B7"];

function MapView({
  run, nodes, currentConnections, onChoosePath, pending,
}: {
  run: RunState;
  nodes: NodeState[];
  currentConnections: number;
  onChoosePath: (nodeId: number) => void;
  pending: boolean;
}) {
  // Group nodes by column (8 columns: 0-7)
  const columns: NodeState[][] = [];
  for (let col = 0; col <= 7; col++) {
    const colNodes = nodes
      .filter(n => n.column === col)
      .sort((a, b) => a.row - b.row);
    if (colNodes.length > 0) columns.push(colNodes);
  }

  return (
    <div className="card map-card">
      <div className="map-header">
        <h3 className="card-title" style={{ margin: 0 }}>Dungeon Map</h3>
        <span className="map-score">Score: {run.score}</span>
      </div>
      <div className="map-container">
        {columns.map((colNodes, colIdx) => (
          <div key={colIdx} className="map-column">
            {colNodes.map((node) => {
              const isCurrent = run.current_node_id === node.node_id;
              const isReachable = hasConnection(currentConnections, node.node_id);
              const isVisited = node.resolved;
              const typeName = NODE_TYPES[node.node_type] ?? "?";
              const isSkillCheck = typeName === "Combat" || typeName === "Event";

              const classes = [
                "node-btn",
                `type-${typeName}`,
                isCurrent ? "current" : "",
                isReachable && !isCurrent ? "reachable" : "",
                isVisited && !isCurrent ? "visited" : "",
                !isCurrent && !isReachable && !isVisited ? "dimmed" : "",
              ].filter(Boolean).join(" ");

              // Skill-check nodes: show skill icon(s) as main content
              // Treasure/Rest/Start/Boss: show their dedicated icon + label
              const skillIcon1 = node.skill_tag_1 ? (SKILL_ICONS[node.skill_tag_1] ?? "") : "";
              const skillIcon2 = node.skill_tag_2 ? (SKILL_ICONS[node.skill_tag_2] ?? "") : "";

              return (
                <button
                  key={node.node_id}
                  className={classes}
                  onClick={() => onChoosePath(node.node_id)}
                  disabled={pending || !isReachable}
                  title={node.skill_tag_1 ? `${node.skill_tag_1}${node.skill_tag_2 ? ` + ${node.skill_tag_2}` : ""}` : typeName}
                >
                  {isSkillCheck ? (
                    <>
                      <span className="node-skill">{skillIcon1}{skillIcon2 ? ` ${skillIcon2}` : ""}</span>
                      {node.difficulty > 0 && <span className="node-diff">{DIFF_DOTS[node.difficulty]}</span>}
                    </>
                  ) : (
                    <>
                      <span className="node-icon">{NODE_ICONS[typeName] ?? "?"}</span>
                      <span className="node-type">{typeName}</span>
                    </>
                  )}
                </button>
              );
            })}
          </div>
        ))}
      </div>
      <p className="map-hint">Move to a connected node by clicking it.</p>
    </div>
  );
}

export default App;
