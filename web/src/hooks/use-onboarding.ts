import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "@/lib/api";
import type { OnboardingStatus } from "@/types";

export function useOnboarding(projectId: number | null) {
  const [status, setStatus] = useState<OnboardingStatus | null>(null);
  const [loading, setLoading] = useState(false);

  // Used to drop responses for a project we've since switched away from.
  const activeProjectRef = useRef<number | null>(projectId);

  const refresh = useCallback(async () => {
    if (!projectId) return;
    try {
      const data = await api.getOnboarding(projectId);
      if (activeProjectRef.current === projectId) {
        setStatus(data);
      }
    } catch {
      // ignore — surface a "not available" state via null
    }
  }, [projectId]);

  useEffect(() => {
    activeProjectRef.current = projectId;
    if (!projectId) {
      setStatus(null);
      return;
    }
    // Clear stale status from the previous project so the gate in
    // AppLayout shows the loading placeholder rather than a stale fork.
    setStatus(null);
    setLoading(true);
    refresh().finally(() => setLoading(false));
  }, [projectId, refresh]);

  const markCompleted = useCallback(async () => {
    if (!projectId) return;
    const updated = await api.completeOnboarding(projectId);
    if (activeProjectRef.current === projectId) {
      setStatus(updated);
    }
  }, [projectId]);

  return { status, loading, refresh, markCompleted };
}
