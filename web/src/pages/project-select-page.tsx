import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "@/lib/api";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export function ProjectSelectPage() {
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api
      .listProjects()
      .then((projects) => {
        if (projects.length > 0) {
          navigate(`/product/${projects[0].id}`, { replace: true });
        } else {
          setError("No projects yet. Create one to get started.");
        }
      })
      .catch(() => setError("Failed to load projects."));
  }, [navigate]);

  if (error) {
    return (
      <div className="flex h-screen items-center justify-center bg-[var(--paper)]">
        <Card className="max-w-sm">
          <CardContent className="py-8 text-center text-sm text-[var(--ink-soft)]">
            {error}
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex h-screen items-center justify-center bg-[var(--paper)]">
      <Skeleton className="h-8 w-48" />
    </div>
  );
}
