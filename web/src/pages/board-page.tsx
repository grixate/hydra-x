import { useState, useEffect, useMemo } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { UniversalInput } from "@/components/chat/universal-input";
import { GraphChatCard } from "@/components/chat/chat-card";
import { useChatState } from "@/hooks/use-chat-state";
import {
  DndContext,
  DragOverlay,
  closestCorners,
  PointerSensor,
  useSensor,
  useSensors,
  type DragStartEvent,
  type DragEndEvent,
} from "@dnd-kit/core";
import { SortableContext, verticalListSortingStrategy } from "@dnd-kit/sortable";
import { useSortable } from "@dnd-kit/sortable";
import { CSS } from "@dnd-kit/utilities";
import { api } from "@/lib/api";
import type { ProductTask } from "@/types";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";
import { Plus, Network } from "lucide-react";

const columns = [
  { key: "backlog", label: "Backlog" },
  { key: "ready", label: "Ready" },
  { key: "in_progress", label: "In Progress" },
  { key: "review", label: "Review" },
  { key: "done", label: "Done" },
];

const priorityColors: Record<string, string> = {
  critical: "bg-red-500",
  high: "bg-orange-500",
  medium: "bg-yellow-500",
  low: "bg-slate-300",
};

export function BoardPage() {
  const { projectId } = useParams<{ projectId: string }>();
  const navigate = useNavigate();
  const chat = useChatState(Number(projectId), "strategist");
  const [tasks, setTasks] = useState<ProductTask[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [activeTask, setActiveTask] = useState<ProductTask | null>(null);
  const [detailTask, setDetailTask] = useState<ProductTask | null>(null);

  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 8 } }));

  useEffect(() => {
    if (!projectId) return;
    setLoading(true);
    setError(null);
    api.listTasks(Number(projectId))
      .then(setTasks)
      .catch((err) => setError(err.message ?? "Failed to load"))
      .finally(() => setLoading(false));
  }, [projectId]);

  const grouped = useMemo(() => {
    const map: Record<string, ProductTask[]> = {};
    for (const col of columns) map[col.key] = [];
    for (const t of tasks) (map[t.status] ??= []).push(t);
    return map;
  }, [tasks]);

  function handleDragStart(event: DragStartEvent) {
    const task = tasks.find((t) => t.id === event.active.id);
    setActiveTask(task ?? null);
  }

  function handleDragEnd(event: DragEndEvent) {
    setActiveTask(null);
    const { active, over } = event;
    if (!over || !projectId) return;

    const taskId = active.id as number;
    const newStatus = over.id as string;
    const task = tasks.find((t) => t.id === taskId);
    if (!task || task.status === newStatus) return;

    // Optimistic update
    setTasks((prev) => prev.map((t) => (t.id === taskId ? { ...t, status: newStatus } : t)));
    api.updateTask(Number(projectId), taskId, { status: newStatus }).catch(() => {
      // Revert on failure
      setTasks((prev) => prev.map((t) => (t.id === taskId ? { ...t, status: task.status } : t)));
    });
  }

  async function handleQuickAdd(status: string, title: string) {
    if (!projectId || !title.trim()) return;
    const created = await api.createTask(Number(projectId), { title, body: "", priority: "medium" });
    if (created) {
      const withStatus = { ...created, status };
      setTasks((prev) => [...prev, withStatus]);
      if (status !== "backlog") {
        api.updateTask(Number(projectId), created.id, { status });
      }
    }
  }

  if (loading) {
    return (
      <div className="p-6 space-y-4">
        <Skeleton className="h-8 w-32" />
        <div className="flex gap-4">{columns.map((c) => <Skeleton key={c.key} className="h-64 w-60" />)}</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-6">
        <Card><CardContent className="py-8 text-center text-sm text-muted-foreground">{error}</CardContent></Card>
      </div>
    );
  }

  return (
    <div className="relative flex h-full flex-col">
      <div className="shrink-0 border-b px-6 py-4">
        <h1 className="text-xl font-semibold">Board</h1>
      </div>
      <div className="flex-1 overflow-x-auto p-6 pb-24">
        <DndContext sensors={sensors} collisionDetection={closestCorners} onDragStart={handleDragStart} onDragEnd={handleDragEnd}>
          <div className="flex gap-4">
            {columns.map((col) => (
              <BoardColumn
                key={col.key}
                id={col.key}
                label={col.label}
                tasks={grouped[col.key] ?? []}
                onCardClick={setDetailTask}
                onQuickAdd={(title) => handleQuickAdd(col.key, title)}
              />
            ))}
          </div>
          <DragOverlay>
            {activeTask && <TaskCardStatic task={activeTask} />}
          </DragOverlay>
        </DndContext>
      </div>

      <Sheet open={!!detailTask} onOpenChange={(open) => !open && setDetailTask(null)}>
        <SheetContent className="w-[420px] sm:w-[540px] overflow-y-auto">
          {detailTask && (
            <>
              <SheetHeader>
                <SheetTitle>{detailTask.title}</SheetTitle>
              </SheetHeader>
              <div className="mt-4 space-y-4">
                <div className="flex items-center gap-2">
                  <Badge variant="outline">{detailTask.status}</Badge>
                  {detailTask.priority && <Badge className={cn("text-white text-[10px]", priorityColors[detailTask.priority])}>{detailTask.priority}</Badge>}
                </div>
                {detailTask.body && <p className="text-sm text-muted-foreground whitespace-pre-wrap">{detailTask.body}</p>}
                {detailTask.assignee && <p className="text-sm"><span className="text-muted-foreground">Assigned:</span> {detailTask.assignee}</p>}
                {detailTask.effort_estimate && <p className="text-sm"><span className="text-muted-foreground">Effort:</span> {detailTask.effort_estimate}</p>}
                <Button
                  variant="outline"
                  size="sm"
                  className="mt-2"
                  onClick={() => {
                    setDetailTask(null);
                    navigate(`/projects/${projectId}/graph?focus=task-${detailTask.id}`);
                  }}
                >
                  <Network className="mr-1.5 h-3.5 w-3.5" />
                  View in graph
                </Button>
              </div>
            </>
          )}
        </SheetContent>
      </Sheet>

      <UniversalInput
        surface="board"
        projectId={Number(projectId)}
        onSubmit={chat.handleChatSubmit}
        currentAgent={chat.activeTab?.agent ?? "strategist"}
        onAgentChange={chat.handleAgentChange}
      />

      {chat.chatCardOpen && (
        <GraphChatCard
          tabs={chat.chatTabs}
          activeIndex={chat.activeTabIndex}
          minimized={chat.chatCardMinimized}
          onTabClick={chat.handleTabClick}
          onAddTab={chat.handleAddTab}
          onMinimize={() => chat.setChatCardMinimized((prev) => !prev)}
          onClose={() => chat.setChatCardOpen(false)}
          onGraphCommand={() => {}}
        />
      )}
    </div>
  );
}

function BoardColumn({
  id,
  label,
  tasks,
  onCardClick,
  onQuickAdd,
}: {
  id: string;
  label: string;
  tasks: ProductTask[];
  onCardClick: (t: ProductTask) => void;
  onQuickAdd: (title: string) => void;
}) {
  const [addingTitle, setAddingTitle] = useState("");
  const [showInput, setShowInput] = useState(false);
  const { setNodeRef } = useSortable({ id, data: { type: "column" } });

  return (
    <div ref={setNodeRef} className="w-[260px] shrink-0">
      <div className="mb-3 flex items-center gap-2">
        <span className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{label}</span>
        <Badge variant="secondary" className="text-[10px]">{tasks.length}</Badge>
      </div>
      <ScrollArea className="max-h-[calc(100vh-220px)]">
        <SortableContext items={tasks.map((t) => t.id)} strategy={verticalListSortingStrategy}>
          <div className="space-y-2">
            {tasks.map((task) => (
              <DraggableTaskCard key={task.id} task={task} onClick={() => onCardClick(task)} />
            ))}
          </div>
        </SortableContext>
      </ScrollArea>
      {showInput ? (
        <form
          className="mt-2"
          onSubmit={(e) => {
            e.preventDefault();
            if (addingTitle.trim()) {
              onQuickAdd(addingTitle.trim());
              setAddingTitle("");
              setShowInput(false);
            }
          }}
        >
          <Input
            autoFocus
            placeholder="Task title..."
            value={addingTitle}
            onChange={(e) => setAddingTitle(e.target.value)}
            onBlur={() => { if (!addingTitle.trim()) setShowInput(false); }}
            className="text-sm"
          />
        </form>
      ) : (
        <Button variant="ghost" size="sm" className="mt-2 w-full justify-start text-muted-foreground" onClick={() => setShowInput(true)}>
          <Plus className="mr-1 h-3 w-3" /> Add task
        </Button>
      )}
    </div>
  );
}

function DraggableTaskCard({ task, onClick }: { task: ProductTask; onClick: () => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: task.id });
  const style = { transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.5 : 1 };

  return (
    <div ref={setNodeRef} style={style} {...attributes} {...listeners}>
      <Card className="cursor-pointer transition-colors hover:border-primary/50" onClick={onClick}>
        <CardContent className="p-3">
          <p className="text-sm font-medium leading-tight">{task.title}</p>
          <div className="mt-1.5 flex items-center gap-2">
            {task.priority && <span className={cn("h-2 w-2 rounded-full", priorityColors[task.priority])} />}
            {task.assignee && <span className="text-[10px] text-muted-foreground">{task.assignee}</span>}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

function TaskCardStatic({ task }: { task: ProductTask }) {
  return (
    <Card className="w-[250px] shadow-lg">
      <CardContent className="p-3">
        <p className="text-sm font-medium">{task.title}</p>
      </CardContent>
    </Card>
  );
}
