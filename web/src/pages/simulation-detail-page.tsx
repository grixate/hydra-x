import { useCallback, useEffect, useRef, useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { Simulation } from "@/types";
import { getSocket } from "@/lib/socket";
import {
  SimulationVisualization,
  type SimAgent,
  type SimZone,
} from "@/components/simulation/simulation-visualization";
import { SimulationResults } from "@/components/simulation/simulation-results";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { Pause, Play, Square, ArrowLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";
import type { Channel } from "phoenix";

const DEFAULT_ZONES: SimZone[] = [
  { name: "Awareness", key: "awareness" },
  { name: "Evaluation", key: "evaluation" },
  { name: "Onboarding", key: "onboarding" },
  { name: "Active Use", key: "active_use" },
];

const ARCHETYPE_NAMES = ["Solo Founder", "Team Lead", "Enterprise PM"];

function generateInitialAgents(count: number, archetypes: string[]): SimAgent[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `agent-${i}`,
    archetype: archetypes[i % archetypes.length],
    currentZone: "awareness",
    engagement: 0.7 + Math.random() * 0.3,
    churned: false,
    converted: false,
    x: undefined,
    y: undefined,
  }));
}

// Simulate agent progression through zones
function advanceAgents(agents: SimAgent[], tick: number, maxTicks: number): SimAgent[] {
  const progress = tick / maxTicks;
  return agents.map((agent) => {
    const seed = hashId(agent.id);
    const speed = 0.3 + (seed % 70) / 100; // 0.3–1.0 base speed
    const agentProgress = progress * speed;

    let zone = "awareness";
    let churned = false;
    let engagement = agent.engagement;
    const churnThreshold = 0.4 + (seed % 40) / 100;

    if (agentProgress > 0.8) {
      if (engagement < churnThreshold) {
        churned = true;
        zone = "active_use";
      } else {
        zone = "active_use";
      }
    } else if (agentProgress > 0.5) {
      zone = "onboarding";
      if ((seed % 7) === 0 && progress > 0.6) {
        churned = true;
        engagement = 0.1;
      }
    } else if (agentProgress > 0.2) {
      zone = "evaluation";
    }

    // Engagement decay
    if (!churned) {
      engagement = Math.max(0.15, engagement - 0.002 + (Math.random() - 0.5) * 0.01);
    }

    return { ...agent, currentZone: zone, churned, engagement, converted: zone === "active_use" && !churned };
  });
}

function hashId(id: string): number {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) | 0;
  return Math.abs(h);
}

type EventLogEntry = {
  tick: number;
  text: string;
  timestamp: string;
};

export function SimulationDetailPage() {
  const { projectId, simId } = useParams<{ projectId: string; simId: string }>();
  const navigate = useNavigate();
  const pid = Number(projectId);
  const sid = Number(simId);

  const [simulation, setSimulation] = useState<Simulation | null>(null);
  const [loading, setLoading] = useState(true);
  const [agents, setAgents] = useState<SimAgent[]>([]);
  const [tick, setTick] = useState(0);
  const [paused, setPaused] = useState(false);
  const [hoveredAgent, setHoveredAgent] = useState<SimAgent | null>(null);
  const [eventLog, setEventLog] = useState<EventLogEntry[]>([]);
  const [logOpen, setLogOpen] = useState(false);

  const channelRef = useRef<Channel | null>(null);
  const tickIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Load simulation
  useEffect(() => {
    if (!pid || !sid) return;
    api
      .getSimulation(pid, sid)
      .then((sim) => {
        setSimulation(sim);
        if (sim.status === "running" || sim.status === "configuring") {
          // Initialize agents for visualization
          const archNames =
            sim.archetype_summary && Array.isArray(sim.archetype_summary)
              ? sim.archetype_summary.map((a) => a.title || "Unknown")
              : ARCHETYPE_NAMES;
          const count = sim.population_size ?? (sim.metadata?.population_size as number) ?? 200;
          const initial = generateInitialAgents(count, archNames);
          setAgents(initial);
        }
      })
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [pid, sid]);

  // Connect to Phoenix channel for real-time updates
  useEffect(() => {
    if (!simulation || (simulation.status !== "running" && simulation.status !== "configuring")) return;
    const socket = getSocket();
    const ch = socket.channel(`simulation:${sid}`, {});
    ch.join()
      .receive("ok", () => {})
      .receive("error", () => {});

    ch.on("tick_complete", (payload) => {
      setTick(payload.tick);
      // Update agents from server state if provided
      if (payload.agent_states?.length) {
        setAgents((prev) =>
          prev.map((agent, i) => {
            const serverState = payload.agent_states[i];
            if (!serverState) return agent;
            return { ...agent, ...serverState };
          }),
        );
      }
      // Add events to log
      if (payload.events?.length) {
        const newEntries: EventLogEntry[] = payload.events.map((e: { description?: string; type: string }) => ({
          tick: payload.tick,
          text: e.description || e.type,
          timestamp: new Date().toLocaleTimeString(),
        }));
        setEventLog((prev) => [...newEntries, ...prev].slice(0, 100));
      }
    });

    ch.on("lifecycle", (payload) => {
      if (payload.event === "completed" || payload.event === "failed") {
        // Reload simulation to get results
        api.getSimulation(pid, sid).then(setSimulation).catch(() => {});
      }
      if (payload.event === "paused") setPaused(true);
      if (payload.event === "resumed") setPaused(false);
    });

    channelRef.current = ch;
    return () => {
      ch.leave();
      channelRef.current = null;
    };
  }, [simulation?.status, sid, pid]);

  // Track maxTicks in a ref to avoid re-creating the interval when simulation object changes
  const maxTicksRef = useRef(50);
  useEffect(() => {
    if (simulation) {
      maxTicksRef.current = simulation.max_ticks ?? (simulation.metadata?.max_ticks as number) ?? 50;
    }
  }, [simulation]);

  // Client-side tick simulation (for demo / when server doesn't push ticks)
  const simStatus = simulation?.status;
  useEffect(() => {
    if (simStatus !== "running" && simStatus !== "configuring") return;
    if (paused) return;

    tickIntervalRef.current = setInterval(() => {
      setTick((prev) => {
        const next = prev + 1;
        if (next >= maxTicksRef.current) {
          if (tickIntervalRef.current) clearInterval(tickIntervalRef.current);
          api.getSimulation(pid, sid).then(setSimulation).catch(() => {});
          return maxTicksRef.current;
        }
        return next;
      });
    }, 1500);

    return () => {
      if (tickIntervalRef.current) clearInterval(tickIntervalRef.current);
    };
  }, [simStatus, paused, pid, sid]);

  // Advance agents on tick change
  useEffect(() => {
    setAgents((prev) => {
      if (prev.length === 0) return prev;
      return advanceAgents(prev, tick, maxTicksRef.current);
    });
  }, [tick]);

  // Keep a ref to agents for the event log generator (avoids re-running on every agents change)
  const agentsSnapshotRef = useRef(agents);
  agentsSnapshotRef.current = agents;

  // Generate demo event log entries every 3 ticks
  useEffect(() => {
    if (tick === 0 || tick % 3 !== 0) return;
    const currentAgents = agentsSnapshotRef.current;
    if (currentAgents.length === 0) return;

    const churned = currentAgents.filter((a) => a.churned);
    const active = currentAgents.filter((a) => !a.churned);
    const entries: EventLogEntry[] = [];
    const ts = new Date().toLocaleTimeString();

    if (churned.length > 0 && Math.random() > 0.5) {
      const a = churned[Math.floor(Math.random() * churned.length)];
      entries.push({ tick, text: `Agent ${a.id.split("-")[1]} (${a.archetype}) churned at ${a.currentZone.replace("_", " ")}`, timestamp: ts });
    }
    if (active.length > 0 && Math.random() > 0.6) {
      const a = active[Math.floor(Math.random() * active.length)];
      entries.push({ tick, text: `Agent ${a.id.split("-")[1]} (${a.archetype}) progressed to ${a.currentZone.replace("_", " ")}`, timestamp: ts });
    }

    if (entries.length > 0) {
      setEventLog((prev) => [...entries, ...prev].slice(0, 100));
    }
  }, [tick]);

  const handleStop = useCallback(() => {
    // In production, would send stop command via channel
    if (tickIntervalRef.current) clearInterval(tickIntervalRef.current);
    api.getSimulation(pid, sid).then(setSimulation).catch(() => {});
  }, [pid, sid]);

  if (loading) {
    return (
      <div className="h-full p-6">
        <Skeleton className="h-full w-full rounded-lg" />
      </div>
    );
  }

  if (!simulation) {
    return (
      <div className="flex h-full items-center justify-center text-sm text-muted-foreground">
        Simulation not found
      </div>
    );
  }

  // Completed / failed → show results
  if (simulation.status === "completed" || simulation.status === "failed") {
    return (
      <div className="h-full overflow-auto">
        <div className="mx-auto max-w-2xl px-4 pt-4">
          <button
            onClick={() => navigate(`/projects/${projectId}/simulation`)}
            className="mb-2 flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <ArrowLeft className="h-3 w-3" /> Back to simulations
          </button>
        </div>
        <SimulationResults
          simulation={simulation}
          onImportToGraph={(ids) => {
            api.importSimulationResults(pid, sid).catch(() => {});
            console.log("Import:", ids);
          }}
          onStartBoardSession={() => navigate(`/projects/${projectId}/board`)}
        />
      </div>
    );
  }

  // Running / configuring → show live visualization
  const maxTicks = simulation.max_ticks ?? (simulation.metadata?.max_ticks as number) ?? 50;
  const activeCount = agents.filter((a) => !a.churned).length;
  const churnedCount = agents.filter((a) => a.churned).length;
  const convertedCount = agents.filter((a) => a.converted).length;
  const costSoFar = ((simulation.metadata?.cost_cents as number) ?? tick * 0.7) / 100;
  const title = (simulation.metadata?.title as string) ?? `Simulation #${simulation.id}`;

  return (
    <div className="flex h-full flex-col">
      {/* Top bar */}
      <div className="flex items-center justify-between border-b px-4 py-2">
        <div className="flex items-center gap-3">
          <button
            onClick={() => navigate(`/projects/${projectId}/simulation`)}
            className="text-muted-foreground hover:text-foreground transition-colors"
          >
            <ArrowLeft className="h-4 w-4" />
          </button>
          <span className="text-sm font-medium">{title}</span>
          <span className="rounded-full bg-blue-100 px-2 py-0.5 text-[10px] font-medium text-blue-800">
            Running
          </span>
        </div>
        <div className="flex items-center gap-4 text-xs text-muted-foreground">
          <span>{tick}/{maxTicks} ticks</span>
          <span>${costSoFar.toFixed(2)} spent</span>
        </div>
      </div>

      {/* Main viz area */}
      <div className="relative flex-1">
        <SimulationVisualization
          agents={agents}
          zones={DEFAULT_ZONES}
          tick={tick}
          maxTicks={maxTicks}
          paused={paused}
          onAgentHover={setHoveredAgent}
        />

        {/* Agent tooltip */}
        {hoveredAgent && (
          <div className="absolute left-4 top-4 rounded-lg border bg-background/95 px-3 py-2 text-xs shadow-lg backdrop-blur-sm">
            <p className="font-medium">{hoveredAgent.archetype}</p>
            <p className="text-muted-foreground">
              Zone: {hoveredAgent.currentZone.replace("_", " ")} &middot;
              Engagement: {(hoveredAgent.engagement * 100).toFixed(0)}%
            </p>
            {hoveredAgent.churned && <p className="text-red-500">Churned</p>}
            {hoveredAgent.converted && <p className="text-green-600">Converted</p>}
          </div>
        )}

        {/* Event log panel */}
        <div
          className={cn(
            "absolute right-0 top-0 h-full border-l bg-background/95 backdrop-blur-sm transition-all duration-200",
            logOpen ? "w-72" : "w-0",
          )}
        >
          {logOpen && (
            <div className="flex h-full flex-col">
              <div className="flex items-center justify-between border-b px-3 py-2">
                <span className="text-xs font-medium">Event log</span>
                <button onClick={() => setLogOpen(false)} className="text-muted-foreground hover:text-foreground">
                  <ChevronRight className="h-3.5 w-3.5" />
                </button>
              </div>
              <div className="flex-1 overflow-auto px-3 py-2">
                {eventLog.map((entry, i) => (
                  <div key={i} className="mb-1.5 text-[11px] leading-relaxed">
                    <span className="text-muted-foreground/60">{entry.timestamp}</span>{" "}
                    <span className="text-foreground/80">{entry.text}</span>
                  </div>
                ))}
                {eventLog.length === 0 && (
                  <p className="py-4 text-center text-[11px] text-muted-foreground">
                    Events will appear as the simulation runs...
                  </p>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Log toggle button */}
        {!logOpen && (
          <button
            onClick={() => setLogOpen(true)}
            className="absolute right-3 top-3 rounded-md border bg-background/80 px-2.5 py-1.5 text-[10px] font-medium text-muted-foreground shadow-sm backdrop-blur-sm hover:bg-background transition-colors"
          >
            Event log
          </button>
        )}
      </div>

      {/* Bottom bar */}
      <div className="flex items-center justify-between border-t px-4 py-2.5">
        <div className="flex items-center gap-5 text-xs">
          <span>
            Active: <span className="font-medium text-foreground">{activeCount}</span>
          </span>
          <span>
            Churned: <span className="font-medium text-red-500">{churnedCount}</span>
          </span>
          <span>
            Converted: <span className="font-medium text-green-600">{convertedCount}</span>
          </span>
        </div>
        <div className="flex items-center gap-2">
          <Button
            variant="outline"
            size="sm"
            onClick={() => setPaused((p) => !p)}
          >
            {paused ? (
              <>
                <Play className="mr-1 h-3 w-3" /> Resume
              </>
            ) : (
              <>
                <Pause className="mr-1 h-3 w-3" /> Pause
              </>
            )}
          </Button>
          <Button variant="outline" size="sm" onClick={handleStop}>
            <Square className="mr-1 h-3 w-3" /> Stop
          </Button>
        </div>
      </div>
    </div>
  );
}
