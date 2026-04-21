import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import { ProjectRail } from "./project-rail";
import { Skeleton } from "@/components/ui/skeleton";

export function LandingLayout() {
  const navigate = useNavigate();
  const [checking, setChecking] = useState(true);
  const [hasProjects, setHasProjects] = useState(true);

  useEffect(() => {
    api
      .listProjects()
      .then((p) => {
        if (p.length === 0) {
          // No projects — redirect to onboarding
          navigate("/projects/new", { replace: true });
        } else {
          setHasProjects(true);
        }
      })
      .catch((err) => {
        // If unauthorized, redirect to auth
        if (err?.status === 401 || err?.message?.includes("401")) {
          navigate("/auth", { replace: true });
        } else {
          setHasProjects(true);
        }
      })
      .finally(() => setChecking(false));
  }, [navigate]);

  if (checking) {
    return (
      <div className="flex h-screen items-center justify-center bg-background">
        <Skeleton className="h-8 w-48" />
      </div>
    );
  }

  if (!hasProjects) return null;

  return (
    <div className="flex h-screen bg-background text-foreground">
      <ProjectRail />
      <main className="flex-1 flex items-center justify-center">
        <div className="text-center">
          <h1 className="text-xl font-semibold">Welcome to Hydra</h1>
          <p className="mt-2 text-muted-foreground text-sm">
            Select a project from the sidebar to get started.
          </p>
        </div>
      </main>
    </div>
  );
}
