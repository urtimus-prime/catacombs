import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useAccount, useConnect, useDisconnect } from "@starknet-react/core";
import { useDojoSDK } from "@dojoengine/sdk/react";
import { RpcProvider } from "starknet";
import { NODE_TYPES, RUN_STATUS } from "./dojo/models";
import { RPC_URL } from "./dojo/config";
import "./App.css";

const EXPLORER_URL = import.meta.env.VITE_EXPLORER_URL ?? "";
// Bump CAT_VIEWER_VERSION when rebuilding Godot, then upload to R2 under the new path
const CAT_VIEWER_VERSION = "v1";
const CAT_VIEWER_BASE = import.meta.env.DEV
  ? "/cat-viewer"
  : `https://pub-f5ae3b0da5d447b4b4f6a8cd2270c415.r2.dev/cat-viewer/${CAT_VIEWER_VERSION}`;

const NODE_ICONS: Record<string, string> = {
  Start: "\u2302", Combat: "\u2694", Treasure: "\u2666",
  Rest: "\u2665", Event: "\u2605", Shop: "\u2617", Boss: "\u2620",
};

interface TxLog {
  id: number;
  action: string;
  txHash: string;
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
  floor: number; max_floors: number; status: number;
  score: number; nodes_visited: number;
}

interface NodeState {
  node_id: number; node_type: number; connections: number; resolved: boolean;
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
    floor: n(4), max_floors: n(5), status: n(6),
    score: n(7), nodes_visited: n(8),
  };
}

function parseNode(r: any[]): NodeState {
  const n = (i: number) => Number(BigInt(r[i]));
  return {
    node_id: n(1), node_type: n(3), connections: n(6), resolved: !!n(4),
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
  const [cat, setCat] = useState<CatState | null>(null);
  const [run, setRun] = useState<RunState | null>(null);
  const [nodes, setNodes] = useState<NodeState[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [txLogs, setTxLogs] = useState<TxLog[]>([]);
  const txIdRef = useRef(1);

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
        setCat(parsed);
      } else {
        setCat(null);
      }
    } catch { setCat(null); }
  }, [client]);

  const fetchRun = useCallback(async (runId: number) => {
    try {
      const result = await client.run_actions.get_run(runId);
      if (result && Number(BigInt(result[0])) > 0) {
        const r = parseRun(result);
        setRun(r);
        const nodePromises = [];
        for (let i = 0; i <= 6; i++) {
          nodePromises.push(client.run_actions.get_node(runId, i));
        }
        const nodeResults = await Promise.all(nodePromises);
        setNodes(nodeResults.map(parseNode));
      } else {
        setRun(null);
        setNodes([]);
      }
    } catch { setRun(null); setNodes([]); }
  }, [client]);

  const addTxLog = useCallback((action: string, txHash: string) => {
    const id = txIdRef.current++;
    setTxLogs(prev => [{ id, action, txHash, timestamp: Date.now() }, ...prev]);
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
    async (fn: () => Promise<any>, actionName: string, onConfirmed?: () => Promise<void>) => {
      if (!account) return;
      setError(null);
      setSuccess(null);
      setPending(true);
      try {
        const result = await fn();
        if (result?.transaction_hash) {
          addTxLog(actionName, result.transaction_hash);
          await rpcProvider.waitForTransaction(result.transaction_hash, { retryInterval: 500 });
        }
        if (onConfirmed) {
          await onConfirmed();
        }
        setSuccess(actionName);
      } catch (e: any) {
        setError(e.message ?? String(e));
      } finally {
        setPending(false);
      }
    },
    [account, addTxLog]
  );

  const createCat = () =>
    wrap(
      () => client.cat_actions.create_cat(account!, "12345"),
      "Create Cat",
      async () => {
        const catId = catRef.current?.id ?? 1;
        await pollUntil(
          () => client.cat_actions.get_cat(catId),
          (r) => { try { return parseCat(r).max_hp > 0; } catch { return false; } },
        );
        await fetchCat(catId);
      },
    );

  const startRun = () =>
    wrap(
      () => client.run_actions.start_run(account!, catRef.current?.id ?? 1),
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
                if (r.cat_id > 0 && r.status === 0) return id;
              } catch { continue; }
            }
            return -1;
          },
          (id) => id > 0,
        );
        if (found && found > 0) {
          await fetchRun(found);
        }
      },
    );

  const choosePath = (nodeId: number) =>
    wrap(
      () => {
        const r = runRef.current;
        if (!r) return Promise.resolve();
        return client.run_actions.choose_path(account!, r.id, nodeId);
      },
      `Choose Path \u2192 Node ${nodeId}`,
      async () => {
        const r = runRef.current;
        if (!r) return;
        // Poll until current_node_id changes to the new node
        await pollUntil(
          () => client.run_actions.get_run(r.id),
          (result) => {
            try { return parseRun(result).current_node_id === nodeId; }
            catch { return false; }
          },
        );
        await fetchRun(r.id);
      },
    );

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
          await pollUntil(
            () => client.run_actions.get_run(r.id),
            (result) => {
              try { return parseRun(result).status !== 0; }
              catch { return false; }
            },
          );
          await fetchRun(r.id);
        }
        await fetchCat(catRef.current?.id ?? 1);
      },
    );

  // Auto-fetch on connect
  useEffect(() => {
    if (!address || !client) return;
    fetchCat(1);
    (async () => {
      for (let id = 10; id >= 1; id--) {
        try {
          const result = await client.run_actions.get_run(id);
          const r = parseRun(result);
          if (r.cat_id > 0 && r.status === 0) {
            await fetchRun(id);
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
  }, [address, client, fetchCat, fetchRun]);

  const connected = !!address;
  const currentNode = nodes.find(n => n.node_id === run?.current_node_id);
  const currentNodeType = currentNode ? NODE_TYPES[currentNode.node_type] : undefined;
  const catAnimation = connected ? getCatAnimation(run, currentNodeType, pending) : "Cat_Idle";
  const catScene = connected ? getCatScene(currentNodeType) : "cosmic_void";
  const viewerSlotClass = connected ? `cat-viewer-slot slot-${tab}` : "cat-viewer-slot slot-connect";

  return (
    <div className={connected ? "app" : "connect-screen"}>
      {/* Always-mounted cat viewer — never unmounts across screens or tabs */}
      <div className={viewerSlotClass}>
        <CatViewer animation={catAnimation} scene={catScene} autoRotate={!connected} />
      </div>

      {/* ===== CONNECT SCREEN ===== */}
      {!connected && (
        <div className="connect-card">
          <h1 className="connect-title">Catacombs</h1>
          <p className="connect-subtitle">An on-chain roguelike for cats</p>
          <div className="connect-divider" />
          {autoConnecting ? (
            <p className="connect-status">Connecting...</p>
          ) : (
            <button
              className="connect-btn"
              onClick={() => connect({ connector: connectors[0] })}
            >
              Enter the Catacombs
            </button>
          )}
        </div>
      )}

      {/* Alerts */}
      {connected && error && <div className="alert alert-error">{error}</div>}
      {connected && success && <div className="alert alert-success">{success}</div>}

      {/* ===== CATS TAB ===== */}
      {connected && tab === "cats" && (
        <div className="tab-content">
          <div className="card">
            <h3 className="card-title">Cat</h3>
            {cat ? (
              <>
                <div className="stats-grid">
                  <StatCell label="ID" value={`#${cat.id}`} />
                  <StatCell label="Level" value={cat.level} accent />
                  <StatCell label="XP" value={cat.xp} />
                  <StatCell label="HP" value={`${cat.hp}/${cat.max_hp}`}
                    hpLevel={cat.hp / cat.max_hp} />
                  <StatCell label="ATK" value={cat.attack} />
                  <StatCell label="DEF" value={cat.defense} />
                  <StatCell label="SPD" value={cat.speed} />
                  <StatCell label="LCK" value={cat.luck} />
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
                  {!cat.alive && <span className="wounded"> &mdash; wounded</span>}
                </div>
              </>
            ) : (
              <div className="empty-state">
                <p>No cat in your roster yet.</p>
                <button className="btn btn-primary" onClick={createCat} disabled={pending}>
                  Summon Cat
                </button>
              </div>
            )}
          </div>
        </div>
      )}

      {/* ===== CATACOMBS TAB ===== */}
      {connected && tab === "catacombs" && (
        <div className="tab-content">
          <div className="panels-column">
              {/* Run Panel */}
              <div className="card">
                <h3 className="card-title">Run</h3>
                {run && run.status === 0 ? (
                  <>
                    <div className="stats-grid">
                      <StatCell label="Run" value={`#${run.id}`} />
                      <StatCell label="Floor" value={`${run.floor}/${run.max_floors}`} />
                      <StatCell label="Position" value={
                        run.current_node_id === 0 ? "Start" :
                        run.current_node_id === 6 ? "Boss" :
                        `Node ${run.current_node_id}`
                      } />
                      <StatCell label="Visited" value={run.nodes_visited} />
                      <StatCell label="Score" value={run.score} accent />
                      <StatCell label="Status" value={RUN_STATUS[run.status]}
                        hpLevel={1} />
                    </div>
                    <div style={{ marginTop: 16 }}>
                      <button className="btn btn-danger" onClick={abandonRun} disabled={pending}>
                        Abandon Run
                      </button>
                    </div>
                  </>
                ) : (
                  <div className="empty-state">
                    <p>
                      {run ? `Last run: ${RUN_STATUS[run.status]}` : "No active run"}
                    </p>
                    {cat ? (
                      <button className="btn btn-primary" onClick={startRun}
                        disabled={pending || !cat.alive}>
                        Begin Descent
                      </button>
                    ) : (
                      <p style={{ fontSize: 12, color: "var(--stone-500)" }}>
                        Summon a cat first in the Cats tab
                      </p>
                    )}
                  </div>
                )}
              </div>

              {/* Quick cat stats */}
              {cat && (
                <div className="card">
                  <h3 className="card-title">Cat #{cat.id}</h3>
                  <div className="stats-grid">
                    <StatCell label="HP" value={`${cat.hp}/${cat.max_hp}`}
                      hpLevel={cat.hp / cat.max_hp} />
                    <StatCell label="ATK" value={cat.attack} />
                    <StatCell label="DEF" value={cat.defense} />
                    <StatCell label="LVL" value={cat.level} accent />
                  </div>
                </div>
              )}
          </div>

          {/* Map */}
          {run && run.status === 0 && (
            <MapView
              run={run}
              nodes={nodes}
              currentConnections={currentNode?.connections ?? 0}
              onChoosePath={choosePath}
              pending={pending}
            />
          )}

          {/* Activity Log */}
          {txLogs.length > 0 && (
            <div className="card">
              <div className="log-header">
                <h3 className="card-title" style={{ margin: 0 }}>Activity Log</h3>
                <button className="btn-clear" onClick={() => setTxLogs([])}>Clear</button>
              </div>
              <div className="log-table">
                <div className="log-row log-row-header">
                  <span>#</span>
                  <span>Action</span>
                  <span>Transaction</span>
                  <span style={{ textAlign: "right" }}>Time</span>
                </div>
                {txLogs.map((log) => (
                  <div key={log.id} className="log-row">
                    <span className="log-num">{log.id}</span>
                    <span className="log-action">{log.action}</span>
                    <span>
                      {EXPLORER_URL ? (
                        <a
                          href={`${EXPLORER_URL}/tx/${log.txHash}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="log-hash"
                        >
                          {log.txHash.slice(0, 10)}...{log.txHash.slice(-8)} &#x2197;
                        </a>
                      ) : (
                        <span
                          className="log-hash"
                          style={{ cursor: "pointer" }}
                          onClick={() => navigator.clipboard.writeText(log.txHash)}
                        >
                          {log.txHash.slice(0, 10)}...{log.txHash.slice(-8)} &#x29C9;
                        </span>
                      )}
                    </span>
                    <span className="log-time">
                      {new Date(log.timestamp).toLocaleTimeString()}
                    </span>
                  </div>
                ))}
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
            <div style={{ marginTop: 20 }}>
              <button className="btn btn-danger" onClick={() => disconnect()}>
                Disconnect Wallet
              </button>
            </div>
          </div>

          {/* Full tx history */}
          {txLogs.length > 0 && (
            <div className="card">
              <div className="log-header">
                <h3 className="card-title" style={{ margin: 0 }}>Transaction History</h3>
                <button className="btn-clear" onClick={() => setTxLogs([])}>Clear</button>
              </div>
              <div className="log-table">
                <div className="log-row log-row-header">
                  <span>#</span>
                  <span>Action</span>
                  <span>Transaction</span>
                  <span style={{ textAlign: "right" }}>Time</span>
                </div>
                {txLogs.map((log) => (
                  <div key={log.id} className="log-row">
                    <span className="log-num">{log.id}</span>
                    <span className="log-action">{log.action}</span>
                    <span>
                      {EXPLORER_URL ? (
                        <a
                          href={`${EXPLORER_URL}/tx/${log.txHash}`}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="log-hash"
                        >
                          {log.txHash.slice(0, 10)}...{log.txHash.slice(-8)} &#x2197;
                        </a>
                      ) : (
                        <span
                          className="log-hash"
                          style={{ cursor: "pointer" }}
                          onClick={() => navigator.clipboard.writeText(log.txHash)}
                        >
                          {log.txHash.slice(0, 10)}...{log.txHash.slice(-8)} &#x29C9;
                        </span>
                      )}
                    </span>
                    <span className="log-time">
                      {new Date(log.timestamp).toLocaleTimeString()}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
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

// Animation mapping: node type -> cat animation
const NODE_ANIM: Record<string, string> = {
  Start: "Cat_Idle",
  Combat: "Sword_Attack_Light",
  Treasure: "Cat_HipHop",
  Rest: "Cat_Idle",
  Event: "Looking_Around",
  Shop: "Cat_Idle",
  Boss: "Sword_Attack_Medium",
};

const PENDING_ANIM = "Cat_Walking";
const IDLE_ANIM = "Cat_Idle";
const NO_RUN_ANIM = "Cat_SillyDance";

function getCatAnimation(
  run: RunState | null,
  currentNodeType: string | undefined,
  pending: boolean,
): string {
  if (pending) return PENDING_ANIM;
  if (!run || run.status !== 0) return NO_RUN_ANIM;
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

function CatViewer({ animation, scene, autoRotate = false }: {
  animation: string;
  scene: string;
  autoRotate?: boolean;
}) {
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const prevAnimation = useRef(animation);
  const prevScene = useRef(scene);
  const prevAutoRotate = useRef(autoRotate);

  // Send configure messages when props change
  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe?.contentWindow) return;

    const config: Record<string, any> = {};
    if (animation !== prevAnimation.current) {
      config.animation = animation;
      prevAnimation.current = animation;
    }
    if (scene !== prevScene.current) {
      config.scene = scene;
      prevScene.current = scene;
    }
    if (autoRotate !== prevAutoRotate.current) {
      config.autoRotate = autoRotate;
      prevAutoRotate.current = autoRotate;
    }
    if (Object.keys(config).length > 0) {
      iframe.contentWindow.postMessage(
        { type: "catViewer:configure", config },
        "*"
      );
    }
  }, [animation, scene, autoRotate]);

  const src = useMemo(
    () => `${CAT_VIEWER_BASE}/embed.html?scene=${encodeURIComponent(scene)}&animation=${encodeURIComponent(animation)}&autoRotate=${autoRotate}&camDist=1.5&camY=15&camX=-5`,
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

function MapView({
  run, nodes, currentConnections, onChoosePath, pending,
}: {
  run: RunState;
  nodes: NodeState[];
  currentConnections: number;
  onChoosePath: (nodeId: number) => void;
  pending: boolean;
}) {
  const columns = [[0], [1, 2], [3, 4], [5], [6]];

  return (
    <div className="card">
      <div className="map-header">
        <h3 className="card-title" style={{ margin: 0 }}>Dungeon Map</h3>
        <span className="map-floor">Floor {run.floor}/{run.max_floors}</span>
      </div>
      <div className="map-container">
        {columns.map((col, colIdx) => (
          <div key={colIdx} className="map-column">
            {col.map((nodeId) => {
              const node = nodes.find(n => n.node_id === nodeId);
              const isCurrent = run.current_node_id === nodeId;
              const isReachable = hasConnection(currentConnections, nodeId);
              const typeName = node ? NODE_TYPES[node.node_type] : "?";

              const classes = [
                "node-btn",
                `type-${typeName}`,
                isCurrent ? "current" : "",
                isReachable && !isCurrent ? "reachable" : "",
                !isCurrent && !isReachable ? "dimmed" : "",
              ].filter(Boolean).join(" ");

              return (
                <button
                  key={nodeId}
                  className={classes}
                  onClick={() => onChoosePath(nodeId)}
                  disabled={pending || !isReachable}
                >
                  <span className="node-icon">{NODE_ICONS[typeName] ?? "?"}</span>
                  <span className="node-type">{typeName}</span>
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
