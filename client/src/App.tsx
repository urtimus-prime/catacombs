import { useCallback, useEffect, useState } from "react";
import { useAccount, useConnect, useDisconnect } from "@starknet-react/core";
import { useDojoSDK } from "@dojoengine/sdk/react";
import { RpcProvider } from "starknet";
import { NODE_TYPES, RUN_STATUS } from "./dojo/models";
import { RPC_URL } from "./dojo/config";

const EXPLORER_URL = import.meta.env.VITE_EXPLORER_URL ?? "";

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

function App() {
  const { client } = useDojoSDK();
  const { connect, connectors } = useConnect();
  const { disconnect } = useDisconnect();
  const { account, address } = useAccount();
  const [autoConnecting, setAutoConnecting] = useState(
    () => !!localStorage.getItem("lastUsedConnector")
  );

  useEffect(() => {
    if (address || !localStorage.getItem("lastUsedConnector")) {
      setAutoConnecting(false);
    }
  }, [address]);

  // Timeout fallback in case auto-connect silently fails
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
  const [nextTxId, setNextTxId] = useState(1);

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
        // Fetch all nodes for this run
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
    setTxLogs(prev => [{ id: nextTxId, action, txHash, timestamp: Date.now() }, ...prev]);
    setNextTxId(prev => prev + 1);
  }, [nextTxId]);

  const waitForTx = useCallback(async (txHash: string) => {
    await rpcProvider.waitForTransaction(txHash, { retryInterval: 500 });
  }, []);

  const wrap = useCallback(
    async (fn: () => Promise<any>, actionName: string) => {
      if (!account) return;
      setError(null);
      setSuccess(null);
      setPending(true);
      try {
        const result = await fn();
        if (result?.transaction_hash) {
          addTxLog(actionName, result.transaction_hash);
          await waitForTx(result.transaction_hash);
        }
        setSuccess(actionName);
        return result;
      } catch (e: any) {
        setError(e.message ?? String(e));
      } finally {
        setPending(false);
      }
    },
    [account, addTxLog, waitForTx]
  );

  const createCat = () =>
    wrap(async () => {
      const result = await client.cat_actions.create_cat(account!, "12345");
      return result;
    }, "Create Cat").then(() => fetchCat(cat?.id ?? 1));

  const startRun = () =>
    wrap(async () => {
      const result = await client.run_actions.start_run(account!, cat?.id ?? 1);
      return result;
    }, "Start Run").then(async () => {
      const startId = (run?.id ?? 0) + 1;
      for (let id = startId; id < startId + 10; id++) {
        try {
          const r2 = await client.run_actions.get_run(id);
          const r = parseRun(r2);
          if (r.cat_id > 0 && r.status === 0) {
            await fetchRun(id);
            return;
          }
        } catch { continue; }
      }
    });

  const choosePath = (nodeId: number) =>
    wrap(async () => {
      if (!run) return;
      const result = await client.run_actions.choose_path(account!, run.id, nodeId);
      return result;
    }, `Choose Path → Node ${nodeId}`).then(() => { if (run) fetchRun(run.id); });

  const abandonRun = () =>
    wrap(async () => {
      if (!run) return;
      const result = await client.run_actions.abandon_run(account!, run.id);
      return result;
    }, "Abandon Run").then(() => {
      if (run) fetchRun(run.id);
      fetchCat(cat?.id ?? 1);
    });

  // Auto-fetch cat and find latest active run on connect
  useEffect(() => {
    if (!address || !client) return;
    fetchCat(1);
    // Scan for the latest active run (a valid run has cat_id > 0)
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
      // No active run; show latest completed/failed
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

  if (!address) {
    return (
      <div style={styles.container}>
        <div style={{ ...styles.card, maxWidth: 500, margin: "100px auto", textAlign: "center" }}>
          <h1 style={styles.title}>Catacombs</h1>
          <p style={styles.subtitle}>An on-chain roguelike for cats</p>
          {autoConnecting ? (
            <p style={{ color: "#718096" }}>Connecting...</p>
          ) : (
            <button
              style={styles.button}
              onClick={() => connect({ connector: connectors[0] })}
            >
              Connect Wallet
            </button>
          )}
        </div>
      </div>
    );
  }

  const currentNode = nodes.find(n => n.node_id === run?.current_node_id);

  return (
    <div style={styles.container}>
      <header style={styles.header}>
        <h1 style={styles.headerTitle}>Catacombs</h1>
        <div style={styles.headerRight}>
          <span style={styles.address}>
            {address.slice(0, 6)}...{address.slice(-4)}
          </span>
          <button style={styles.buttonSmall} onClick={() => disconnect()}>
            Logout
          </button>
        </div>
      </header>

      {error && <div style={styles.error}>{error}</div>}
      {success && <div style={styles.success}>{success}</div>}

      <div style={styles.grid}>
        {/* Cat Panel */}
        <div style={styles.card}>
          <h2 style={{ margin: "0 0 12px" }}>Cat</h2>
          {cat ? (
            <div>
              <div style={styles.statGrid}>
                <Stat label="ID" value={`#${cat.id}`} />
                <Stat label="Level" value={cat.level} />
                <Stat label="HP" value={`${cat.hp}/${cat.max_hp}`}
                  color={cat.hp < cat.max_hp / 3 ? "#e53e3e" : cat.hp < cat.max_hp * 0.7 ? "#d69e2e" : "#38a169"} />
                <Stat label="XP" value={cat.xp} />
                <Stat label="ATK" value={cat.attack} />
                <Stat label="DEF" value={cat.defense} />
                <Stat label="SPD" value={cat.speed} />
                <Stat label="LCK" value={cat.luck} />
              </div>
              <div style={{ marginTop: 8, fontSize: 12, color: "#718096" }}>
                Runs: {cat.runs_completed} completed, {cat.runs_failed} failed
                {!cat.alive && <span style={{ color: "#e53e3e" }}> (wounded)</span>}
              </div>
            </div>
          ) : (
            <div>
              <p style={{ color: "#718096", margin: "8px 0 12px" }}>No cat yet</p>
              <button style={styles.button} onClick={createCat} disabled={pending}>
                Create Cat
              </button>
            </div>
          )}
        </div>

        {/* Run Panel */}
        <div style={styles.card}>
          <h2 style={{ margin: "0 0 12px" }}>Run</h2>
          {run && run.status === 0 ? (
            <div>
              <div style={styles.statGrid}>
                <Stat label="Run" value={`#${run.id}`} />
                <Stat label="Floor" value={`${run.floor}/${run.max_floors}`} />
                <Stat label="Position" value={
                  run.current_node_id === 0 ? "Start" :
                  run.current_node_id === 6 ? "Boss" :
                  `Node ${run.current_node_id}`
                } />
                <Stat label="Visited" value={run.nodes_visited} />
                <Stat label="Score" value={run.score} />
                <Stat label="Status" value={RUN_STATUS[run.status]} color="#38a169" />
              </div>
              <div style={{ ...styles.buttonRow, marginTop: 12 }}>
                <button
                  style={{ ...styles.button, ...styles.dangerButton }}
                  onClick={abandonRun}
                  disabled={pending}
                >
                  Abandon Run
                </button>
              </div>
            </div>
          ) : (
            <div>
              <p style={{ color: "#718096", margin: "8px 0" }}>
                {run ? `Last run: ${RUN_STATUS[run.status]}` : "No active run"}
              </p>
              {cat && (
                <button style={styles.button} onClick={startRun} disabled={pending || !cat.alive}>
                  Start Run
                </button>
              )}
            </div>
          )}
        </div>
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
        <div style={styles.card}>
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }}>
            <h2 style={{ margin: 0 }}>Activity Log</h2>
            <button style={styles.buttonSmall} onClick={() => setTxLogs([])}>Clear</button>
          </div>
          <div style={styles.logTable}>
            <div style={styles.logHeader}>
              <span style={{ width: 40 }}>#</span>
              <span style={{ flex: 1 }}>Action</span>
              <span style={{ width: 340 }}>Transaction Hash</span>
              <span style={{ width: 70, textAlign: "right" }}>Time</span>
            </div>
            {txLogs.map((log) => (
              <div key={log.id} style={styles.logRow}>
                <span style={{ width: 40, color: "#718096" }}>{log.id}</span>
                <span style={{ flex: 1, color: "#e2e8f0", fontWeight: "bold" }}>{log.action}</span>
                <span style={{ width: 340 }}>
                  {EXPLORER_URL ? (
                    <a
                      href={`${EXPLORER_URL}/tx/${log.txHash}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      style={styles.txHash}
                      title={`View in Explorer: ${log.txHash}`}
                    >
                      {log.txHash.slice(0, 10)}...{log.txHash.slice(-8)} ↗
                    </a>
                  ) : (
                    <span
                      style={{ ...styles.txHash, cursor: "pointer" }}
                      title="Click to copy full hash"
                      onClick={() => navigator.clipboard.writeText(log.txHash)}
                    >
                      {log.txHash.slice(0, 10)}...{log.txHash.slice(-8)} ⧉
                    </span>
                  )}
                </span>
                <span style={{ width: 70, textAlign: "right", color: "#718096", fontSize: 11 }}>
                  {new Date(log.timestamp).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {pending && <div style={styles.pending}>Processing...</div>}
    </div>
  );
}

function Stat({ label, value, color }: { label: string; value: string | number; color?: string }) {
  return (
    <div style={{ textAlign: "center" }}>
      <div style={{ fontSize: 11, color: "#718096", textTransform: "uppercase" }}>{label}</div>
      <div style={{ fontSize: 16, fontWeight: "bold", color: color ?? "#e2e8f0" }}>{value}</div>
    </div>
  );
}

function MapView({
  run,
  nodes,
  currentConnections,
  onChoosePath,
  pending,
}: {
  run: RunState;
  nodes: NodeState[];
  currentConnections: number;
  onChoosePath: (nodeId: number) => void;
  pending: boolean;
}) {
  const columns = [
    [0],
    [1, 2],
    [3, 4],
    [5],
    [6],
  ];

  return (
    <div style={styles.card}>
      <h2 style={{ margin: "0 0 12px" }}>Map (Floor {run.floor})</h2>
      <div style={styles.mapContainer}>
        {columns.map((col, colIdx) => (
          <div key={colIdx} style={styles.mapColumn}>
            {col.map((nodeId) => {
              const node = nodes.find(n => n.node_id === nodeId);
              const isCurrent = run.current_node_id === nodeId;
              const isReachable = hasConnection(currentConnections, nodeId);
              const typeName = node ? NODE_TYPES[node.node_type] : "?";

              return (
                <NodeButton
                  key={nodeId}
                  nodeId={nodeId}
                  typeName={typeName}
                  isCurrent={isCurrent}
                  isReachable={isReachable}
                  onClick={() => onChoosePath(nodeId)}
                  disabled={pending || !isReachable}
                />
              );
            })}
          </div>
        ))}
      </div>
      <p style={styles.hint}>
        Click a highlighted node to move there. You can only move to connected nodes.
      </p>
    </div>
  );
}

const TYPE_COLORS: Record<string, string> = {
  Start: "#4a5568",
  Combat: "#e53e3e",
  Treasure: "#d69e2e",
  Rest: "#38a169",
  Event: "#805ad5",
  Shop: "#3182ce",
  Boss: "#c53030",
};

function NodeButton({
  nodeId,
  typeName,
  isCurrent,
  isReachable,
  onClick,
  disabled,
}: {
  nodeId: number;
  typeName: string;
  isCurrent: boolean;
  isReachable: boolean;
  onClick: () => void;
  disabled: boolean;
}) {
  const bg = TYPE_COLORS[typeName] ?? "#2d3748";

  return (
    <button
      style={{
        ...styles.nodeButton,
        backgroundColor: bg,
        opacity: isReachable || isCurrent ? 1 : 0.35,
        border: isCurrent ? "2px solid #f6e05e" : isReachable ? "2px solid #63b3ed" : "2px solid #4a5568",
        boxShadow: isCurrent ? "0 0 8px #f6e05e" : isReachable ? "0 0 6px rgba(99,179,237,0.4)" : "none",
        cursor: isReachable && !disabled ? "pointer" : "default",
      }}
      onClick={onClick}
      disabled={disabled}
    >
      <div style={{ fontSize: 11, lineHeight: 1.2 }}>
        {typeName}
        <div style={{ fontSize: 9, color: "#cbd5e0" }}>#{nodeId}</div>
      </div>
    </button>
  );
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    minHeight: "100vh",
    backgroundColor: "#1a1a2e",
    color: "#e2e8f0",
    fontFamily: "'Courier New', monospace",
    padding: "20px",
    maxWidth: "900px",
    margin: "0 auto",
  },
  card: {
    backgroundColor: "#16213e",
    borderRadius: "8px",
    padding: "20px",
    marginBottom: "16px",
    border: "1px solid #2d3748",
  },
  title: {
    fontSize: "48px",
    color: "#e2e8f0",
    margin: "0 0 8px",
  },
  subtitle: {
    color: "#718096",
    marginBottom: "24px",
  },
  header: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    marginBottom: "20px",
    padding: "12px 0",
    borderBottom: "1px solid #2d3748",
  },
  headerTitle: {
    margin: 0,
    fontSize: "24px",
  },
  headerRight: {
    display: "flex",
    alignItems: "center",
    gap: "12px",
  },
  address: {
    fontSize: "14px",
    color: "#718096",
  },
  grid: {
    display: "grid",
    gridTemplateColumns: "1fr 1fr",
    gap: "16px",
  },
  statGrid: {
    display: "grid",
    gridTemplateColumns: "repeat(4, 1fr)",
    gap: "8px",
  },
  buttonRow: {
    display: "flex",
    gap: "8px",
  },
  button: {
    backgroundColor: "#3182ce",
    color: "white",
    border: "none",
    borderRadius: "6px",
    padding: "10px 20px",
    cursor: "pointer",
    fontFamily: "'Courier New', monospace",
    fontSize: "14px",
    fontWeight: "bold",
  },
  buttonSmall: {
    backgroundColor: "#4a5568",
    color: "white",
    border: "none",
    borderRadius: "4px",
    padding: "6px 12px",
    cursor: "pointer",
    fontFamily: "'Courier New', monospace",
    fontSize: "12px",
  },
  dangerButton: {
    backgroundColor: "#e53e3e",
  },
  error: {
    backgroundColor: "#742a2a",
    color: "#feb2b2",
    padding: "10px 16px",
    borderRadius: "6px",
    marginBottom: "16px",
    fontSize: "14px",
  },
  success: {
    backgroundColor: "#22543d",
    color: "#9ae6b4",
    padding: "10px 16px",
    borderRadius: "6px",
    marginBottom: "16px",
    fontSize: "14px",
  },
  pending: {
    position: "fixed" as const,
    bottom: "20px",
    right: "20px",
    backgroundColor: "#2d3748",
    padding: "10px 20px",
    borderRadius: "6px",
    border: "1px solid #4a5568",
  },
  mapContainer: {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    padding: "20px 0",
    gap: "8px",
  },
  mapColumn: {
    display: "flex",
    flexDirection: "column" as const,
    gap: "12px",
    alignItems: "center",
  },
  nodeButton: {
    width: "80px",
    height: "55px",
    borderRadius: "8px",
    color: "#e2e8f0",
    fontFamily: "'Courier New', monospace",
    fontWeight: "bold",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
  },
  hint: {
    color: "#718096",
    fontSize: "12px",
    textAlign: "center" as const,
  },
  logTable: {
    display: "flex",
    flexDirection: "column" as const,
    gap: "2px",
    fontSize: "13px",
    fontFamily: "'Courier New', monospace",
  },
  logHeader: {
    display: "flex",
    alignItems: "center",
    gap: "8px",
    padding: "6px 8px",
    color: "#718096",
    fontSize: "11px",
    textTransform: "uppercase" as const,
    borderBottom: "1px solid #2d3748",
  },
  logRow: {
    display: "flex",
    alignItems: "center",
    gap: "8px",
    padding: "8px",
    borderRadius: "4px",
    backgroundColor: "#1a1a2e",
  },
  txHash: {
    color: "#63b3ed",
    textDecoration: "none",
    fontSize: "12px",
    padding: "2px 6px",
    borderRadius: "3px",
    backgroundColor: "#1a202c",
    border: "1px solid #2d3748",
  },
};

export default App;
