import { useState, useEffect, useCallback } from "react";
import { api } from "@/lib/api";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { ChevronLeft, ChevronRight } from "lucide-react";

const AGENT_LABELS: Record<string, string> = {
  researcher: "Researcher",
  strategist: "Strategist",
  architect: "Architect",
  designer: "Designer",
  memory_agent: "Memory",
};

const AGENT_COLORS: Record<string, string> = {
  researcher: "#3b82f6",
  strategist: "#f59e0b",
  architect: "#64748b",
  designer: "#8b5cf6",
  memory_agent: "#10b981",
};

function formatTokens(t: number): string {
  if (t >= 1_000_000) return `${(t / 1_000_000).toFixed(1)}M`;
  if (t >= 1_000) return `${(t / 1_000).toFixed(0)}K`;
  return String(t);
}

type LogEntry = {
  id: number;
  agent: string;
  model: string;
  tokens_in: number;
  tokens_out: number;
  cost_cents: number;
  inserted_at: string;
};

const PAGE_SIZE = 25;

interface TokenLogProps {
  projectId: number;
}

export function TokenLog({ projectId }: TokenLogProps) {
  const [open, setOpen] = useState(false);
  const [entries, setEntries] = useState<LogEntry[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [loading, setLoading] = useState(false);

  const fetchPage = useCallback(
    (pageNum: number) => {
      setLoading(true);
      api
        .getSpendLog(projectId, PAGE_SIZE, pageNum * PAGE_SIZE)
        .then((data) => {
          setEntries(data.entries);
          setTotal(data.total);
          setPage(pageNum);
        })
        .catch(() => {})
        .finally(() => setLoading(false));
    },
    [projectId],
  );

  useEffect(() => {
    if (!open) return;
    fetchPage(0);
  }, [projectId, open, fetchPage]);

  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  return (
    <Card>
      <CardHeader className="cursor-pointer" onClick={() => setOpen(!open)}>
        <div className="flex items-center justify-between">
          <CardTitle className="text-sm font-medium">
            Token log
            {total > 0 && open && (
              <span className="ml-2 text-xs font-normal text-muted-foreground">
                {total} entries
              </span>
            )}
          </CardTitle>
          <span className="text-xs text-muted-foreground">
            {open ? "▲ Hide" : "▼ Show recent calls"}
          </span>
        </div>
      </CardHeader>
      {open && (
        <CardContent>
          {entries.length === 0 && !loading ? (
            <p className="text-sm text-muted-foreground py-4 text-center">
              No token usage records yet.
            </p>
          ) : (
            <>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Time</TableHead>
                    <TableHead>Agent</TableHead>
                    <TableHead>Model</TableHead>
                    <TableHead className="text-right">Input</TableHead>
                    <TableHead className="text-right">Output</TableHead>
                    <TableHead className="text-right">Cost</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {entries.map((e) => (
                    <TableRow key={e.id} className={loading ? "opacity-50" : ""}>
                      <TableCell className="text-xs text-muted-foreground">
                        {new Date(e.inserted_at).toLocaleString(undefined, {
                          month: "short",
                          day: "numeric",
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center gap-1.5">
                          <div
                            className="h-1.5 w-1.5 rounded-full"
                            style={{
                              backgroundColor: AGENT_COLORS[e.agent] ?? "#6b7280",
                            }}
                          />
                          <span className="text-xs">
                            {AGENT_LABELS[e.agent] ?? e.agent}
                          </span>
                        </div>
                      </TableCell>
                      <TableCell className="text-xs text-muted-foreground">
                        {e.model}
                      </TableCell>
                      <TableCell className="text-right text-xs text-muted-foreground">
                        {formatTokens(e.tokens_in)}
                      </TableCell>
                      <TableCell className="text-right text-xs text-muted-foreground">
                        {formatTokens(e.tokens_out)}
                      </TableCell>
                      <TableCell className="text-right text-xs font-medium">
                        ${(e.cost_cents / 100).toFixed(2)}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>

              {/* Pagination */}
              {totalPages > 1 && (
                <div className="mt-3 flex items-center justify-between">
                  <span className="text-xs text-muted-foreground">
                    Page {page + 1} of {totalPages}
                  </span>
                  <div className="flex items-center gap-1">
                    <Button
                      variant="outline"
                      size="icon-sm"
                      disabled={page === 0 || loading}
                      onClick={() => fetchPage(page - 1)}
                    >
                      <ChevronLeft className="h-3.5 w-3.5" />
                    </Button>
                    <Button
                      variant="outline"
                      size="icon-sm"
                      disabled={page >= totalPages - 1 || loading}
                      onClick={() => fetchPage(page + 1)}
                    >
                      <ChevronRight className="h-3.5 w-3.5" />
                    </Button>
                  </div>
                </div>
              )}
            </>
          )}
        </CardContent>
      )}
    </Card>
  );
}
