import { useEffect, useRef } from "react";
import {
  forceSimulation,
  forceManyBody,
  forceCollide,
  forceX,
  forceY,
  type Simulation,
  type SimulationNodeDatum,
} from "d3-force";
import { select } from "d3-selection";

export type SimZone = {
  name: string;
  key: string;
};

export type SimAgent = SimulationNodeDatum & {
  id: string;
  archetype: string;
  currentZone: string;
  engagement: number;
  churned: boolean;
  converted: boolean;
};

interface SimulationVisualizationProps {
  agents: SimAgent[];
  zones: SimZone[];
  tick: number;
  maxTicks: number;
  comparison?: boolean;
  paused?: boolean;
  onAgentHover?: (agent: SimAgent | null) => void;
}

const ARCHETYPE_COLORS: Record<string, string> = {
  "Solo Founder": "hsl(210, 80%, 60%)",
  "Team Lead": "hsl(35, 85%, 55%)",
  "Enterprise PM": "hsl(220, 15%, 50%)",
};

function archetypeColor(archetype: string): string {
  return ARCHETYPE_COLORS[archetype] ?? `hsl(${hashStr(archetype) % 360}, 60%, 55%)`;
}

function hashStr(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return Math.abs(h);
}

function zoneY(zone: string, zones: SimZone[], height: number): number {
  const idx = zones.findIndex((z) => z.key === zone);
  if (idx < 0) return height / 2;
  const zoneHeight = height / zones.length;
  return idx * zoneHeight + zoneHeight / 2;
}

export function SimulationVisualization({
  agents,
  zones,
  tick,
  paused,
  onAgentHover,
}: SimulationVisualizationProps) {
  const svgRef = useRef<SVGSVGElement>(null);
  const simRef = useRef<Simulation<SimAgent, undefined> | null>(null);
  const onHoverRef = useRef(onAgentHover);
  onHoverRef.current = onAgentHover;

  // One-time setup: create zones and d3 force simulation
  useEffect(() => {
    if (!svgRef.current) return;
    const svg = select(svgRef.current);

    function setup() {
      if (!svgRef.current) return;
      const width = svgRef.current.clientWidth;
      const height = svgRef.current.clientHeight;
      if (width === 0 || height === 0) return;

      const zoneHeight = height / zones.length;

      // Clear and redraw zones
      svg.selectAll(".zone-group").remove();
      zones.forEach((z, i) => {
        const g = svg.append("g").attr("class", "zone-group");
        g.append("rect")
          .attr("x", 0)
          .attr("y", i * zoneHeight)
          .attr("width", width)
          .attr("height", zoneHeight)
          .attr("fill", i % 2 === 0 ? "transparent" : "hsl(0 0% 50% / 0.04)")
          .attr("stroke", "hsl(0 0% 50% / 0.1)")
          .attr("stroke-dasharray", "4 4");
        g.append("text")
          .attr("x", 20)
          .attr("y", i * zoneHeight + 24)
          .text(z.name.toUpperCase())
          .attr("fill", "hsl(0 0% 50% / 0.35)")
          .attr("font-size", 10)
          .attr("font-weight", 600)
          .attr("letter-spacing", "0.15em");
      });
    }

    setup();
    const resizeObserver = new ResizeObserver(() => {
      setup();
      // Also update force center on resize
      if (simRef.current && svgRef.current) {
        const w = svgRef.current.clientWidth;
        const h = svgRef.current.clientHeight;
        const xForce = simRef.current.force("centerX") as ReturnType<typeof forceX<SimAgent>> | undefined;
        const yForce = simRef.current.force("zoneY") as ReturnType<typeof forceY<SimAgent>> | undefined;
        if (xForce) xForce.x(w / 2);
        if (yForce) yForce.y((d) => zoneY(d.currentZone, zones, h));
        simRef.current.alpha(0.3).restart();
      }
    });
    if (svgRef.current) resizeObserver.observe(svgRef.current);

    return () => {
      resizeObserver.disconnect();
      simRef.current?.stop();
      simRef.current = null;
      svg.selectAll(".agent").remove();
      svg.selectAll(".zone-group").remove();
    };
  }, [zones]);

  // Update agents: sync d3 data and force simulation without tearing down
  useEffect(() => {
    if (!svgRef.current) return;
    const svg = select(svgRef.current);
    const width = svgRef.current.clientWidth;
    const height = svgRef.current.clientHeight;
    if (width === 0 || height === 0) return;

    // Join agent circles
    svg.selectAll<SVGCircleElement, SimAgent>(".agent")
      .data(agents, (d) => d.id)
      .join(
        (enter) =>
          enter
            .append("circle")
            .attr("class", "agent")
            .attr("r", 0)
            .attr("cx", () => width / 2 + (Math.random() - 0.5) * width * 0.6)
            .attr("cy", () => height * 0.1)
            .call((s) => s.transition().duration(600).attr("r", 5)),
        (update) => update,
        (exit) => exit.transition().duration(300).attr("r", 0).remove(),
      )
      .attr("fill", (d) => archetypeColor(d.archetype))
      .attr("opacity", (d) => (d.churned ? 0.12 : d.engagement))
      .attr("r", (d) => (d.churned ? 3 : 5))
      .style("cursor", "pointer")
      .on("mouseenter", function (_, d) {
        select(this).attr("r", 8).attr("stroke", "#fff").attr("stroke-width", 1.5);
        onHoverRef.current?.(d);
      })
      .on("mouseleave", function (_, d) {
        select(this).attr("r", d.churned ? 3 : 5).attr("stroke", "none");
        onHoverRef.current?.(null);
      });

    // Create or update force simulation
    if (!simRef.current) {
      simRef.current = forceSimulation<SimAgent>(agents)
        .force("charge", forceManyBody().strength(-2).distanceMax(60))
        .force("collide", forceCollide<SimAgent>().radius((d) => (d.churned ? 3 : 5)).strength(0.7))
        .force("zoneY", forceY<SimAgent>((d) => zoneY(d.currentZone, zones, height)).strength(0.08))
        .force("centerX", forceX<SimAgent>(width / 2).strength(0.01))
        .velocityDecay(0.4)
        .on("tick", () => {
          svg.selectAll<SVGCircleElement, SimAgent>(".agent")
            .attr("cx", (d) => Math.max(5, Math.min(width - 5, d.x ?? width / 2)))
            .attr("cy", (d) => Math.max(5, Math.min(height - 5, d.y ?? height / 2)));
        });
    } else {
      simRef.current.nodes(agents);
      const yForce = simRef.current.force("zoneY") as ReturnType<typeof forceY<SimAgent>> | undefined;
      if (yForce) yForce.y((d) => zoneY(d.currentZone, zones, height));
      simRef.current.alpha(0.3).restart();
    }
  }, [agents, zones, tick]);

  // Pause/resume
  useEffect(() => {
    if (!simRef.current) return;
    if (paused) {
      simRef.current.stop();
    } else {
      simRef.current.alpha(0.3).restart();
    }
  }, [paused]);

  return <svg ref={svgRef} className="h-full w-full" />;
}
