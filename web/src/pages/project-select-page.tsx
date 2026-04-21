import { useEffect, useState, useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import type { Project } from "@/types";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

export function ProjectSelectPage() {
  const navigate = useNavigate();
  const [projects, setProjects] = useState<Project[] | null>(null);
  const [loading, setLoading] = useState(true);
  const [name, setName] = useState("");
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .listProjects()
      .then((p) => setProjects(p))
      .catch((err) => {
        if (err?.message?.includes("401")) {
          navigate("/auth", { replace: true });
        } else {
          setProjects([]);
        }
      })
      .finally(() => setLoading(false));
  }, [navigate]);

  const handleCreate = useCallback(async () => {
    const trimmed = name.trim();
    if (!trimmed || creating) return;
    setCreating(true);
    try {
      const project = await api.createProject({
        name: trimmed,
        status: "active",
      });

      // Navigate to the onboarding board session if available
      if (project.onboarding_session_id) {
        navigate(`/projects/${project.id}/board/${project.onboarding_session_id}`, {
          replace: true,
        });
      } else {
        navigate(`/projects/${project.id}`, { replace: true });
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to create project");
      setCreating(false);
    }
  }, [name, creating, navigate]);

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

  // No projects — simplified onboarding
  return (
    <div className="flex h-screen flex-col items-center justify-center bg-background px-4">
      <div className="w-full max-w-md space-y-6 text-center">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">
            Welcome to Hydra
          </h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Start by telling us about your product.
            <br />
            Your AI agents will take it from there.
          </p>
        </div>

        <Card>
          <CardContent className="p-5">
            <label className="block text-left text-sm font-medium mb-2">
              What's your product called?
            </label>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. ClearDesk"
              className="w-full rounded-md border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  handleCreate();
                }
              }}
              autoFocus
            />
            <Button
              className="mt-4 w-full"
              onClick={handleCreate}
              disabled={!name.trim() || creating}
            >
              {creating ? "Setting up..." : "Create project"}
            </Button>
          </CardContent>
        </Card>

        {error && (
          <p className="text-sm text-destructive">{error}</p>
        )}
        {creating && !error && (
          <p className="text-sm text-muted-foreground animate-pulse">
            Provisioning your AI team...
          </p>
        )}
      </div>
    </div>
  );
}
