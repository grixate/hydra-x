import { useEffect, useState, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { Project } from "@/types";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { ArrowUp } from "lucide-react";

export function ProjectSelectPage() {
  const navigate = useNavigate();
  const [projects, setProjects] = useState<Project[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [input, setInput] = useState("");
  const [creating, setCreating] = useState(false);

  useEffect(() => {
    api
      .listProjects()
      .then((p) => {
        setProjects(p);
        if (p.length > 0) {
          // If they have projects, show the list (don't auto-redirect)
        }
      })
      .catch(() => setProjects([]))
      .finally(() => setLoading(false));
  }, []);

  const handleSubmit = useCallback(async () => {
    const text = input.trim();
    if (!text || creating) return;
    setCreating(true);
    try {
      // Create a project from the description
      const name = text.length > 60 ? text.slice(0, 57) + "..." : text;
      const project = await api.createProject({
        name,
        description: text,
        status: "active",
      });
      // Start a conversation with the strategist
      const conv = await api.createConversation(project.id, {
        persona: "strategist",
        title: "Project setup",
      });
      await api.sendConversationMessage(
        project.id,
        conv.id,
        `I want to build a product. Here's my idea: ${text}`,
      );
      navigate(`/projects/${project.id}`, { replace: true });
    } catch {
      setCreating(false);
    }
  }, [input, creating, navigate]);

  const handleSuggestion = useCallback(
    (suggestion: string) => {
      if (suggestion === "I already have research to upload") {
        // For existing projects, redirect. For new, create first.
        setInput("I have research documents I'd like to upload and analyze.");
      } else if (suggestion === "I want to start from research") {
        setInput(
          "I want to start a new product from research. I'll upload documents next.",
        );
      } else {
        setInput(
          "I want to build a product. Let me tell you about it.",
        );
      }
    },
    [],
  );

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center bg-background">
        <Skeleton className="h-8 w-48" />
      </div>
    );
  }

  // Has projects — show project list
  if (projects && projects.length > 0) {
    return (
      <div className="flex h-screen items-center justify-center bg-background">
        <div className="w-full max-w-md space-y-4">
          <h1 className="text-center text-2xl font-semibold">Your projects</h1>
          <div className="space-y-2">
            {projects.map((p) => (
              <Card
                key={p.id}
                className="cursor-pointer transition-colors hover:border-primary/50"
                onClick={() => navigate(`/projects/${p.id}`)}
              >
                <CardContent className="p-4">
                  <h3 className="font-medium">{p.name}</h3>
                  {p.description && (
                    <p className="mt-1 text-sm text-muted-foreground line-clamp-2">
                      {p.description}
                    </p>
                  )}
                </CardContent>
              </Card>
            ))}
          </div>
          <Button
            variant="outline"
            className="w-full"
            onClick={() => setProjects([])}
          >
            Create new project
          </Button>
        </div>
      </div>
    );
  }

  // No projects — onboarding
  return (
    <div className="flex h-screen flex-col items-center justify-center bg-background px-4">
      <div className="w-full max-w-2xl space-y-8 text-center">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">
            What are you building?
          </h1>
          <p className="mt-2 text-muted-foreground">
            Tell us about your product and we'll help you structure your
            thinking.
          </p>
        </div>

        {/* Suggestion cards */}
        <div className="flex justify-center gap-3">
          {[
            {
              label: "I have a product idea",
              desc: "Start from a concept",
            },
            {
              label: "I want to start from research",
              desc: "Upload docs first",
            },
            {
              label: "I already have research to upload",
              desc: "Batch import files",
            },
          ].map((s) => (
            <button
              key={s.label}
              type="button"
              onClick={() => handleSuggestion(s.label)}
              className="w-48 rounded-xl border bg-card p-4 text-left shadow-sm transition-all hover:border-primary/50 hover:shadow-md"
            >
              <div className="text-sm font-medium">{s.label}</div>
              <div className="mt-1 text-[11px] text-muted-foreground">
                {s.desc}
              </div>
            </button>
          ))}
        </div>

        {/* Input */}
        <div className="mx-auto w-full max-w-xl">
          <div className="rounded-2xl border bg-background shadow-lg overflow-hidden">
            <div className="px-4 pt-3 pb-1">
              <textarea
                rows={3}
                value={input}
                onChange={(e) => setInput(e.target.value)}
                placeholder="Tell us about your product..."
                className="w-full resize-none bg-transparent text-sm leading-relaxed placeholder:text-muted-foreground focus:outline-none"
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    handleSubmit();
                  }
                }}
              />
            </div>
            <div className="flex items-center justify-end px-3 pb-2.5">
              <Button
                size="icon"
                variant={input.trim() ? "default" : "ghost"}
                className="h-8 w-8 rounded-lg"
                onClick={handleSubmit}
                disabled={!input.trim() || creating}
              >
                <ArrowUp className="h-4 w-4" />
              </Button>
            </div>
          </div>
          {creating && (
            <p className="mt-3 text-sm text-muted-foreground animate-pulse">
              Setting up your project...
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
