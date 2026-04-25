import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import type { OnboardingStatus } from "@/types";

export function useOnboarding(projectId: number | null) {
  const [status, setStatus] = useState<OnboardingStatus | null>(null);
  const [loading, setLoading] = useState(false);

  const refresh = useCallback(async () => {
    if (!projectId) return;
    try {
      const data = await api.getOnboarding(projectId);
      setStatus(data);
    } catch {
      // ignore — surface a "not available" state via null
    }
  }, [projectId]);

  useEffect(() => {
    if (!projectId) {
      setStatus(null);
      return;
    }
    setLoading(true);
    refresh().finally(() => setLoading(false));
  }, [projectId, refresh]);

  const markCompleted = useCallback(async () => {
    if (!projectId) return;
    const updated = await api.completeOnboarding(projectId);
    setStatus(updated);
  }, [projectId]);

  return { status, loading, refresh, markCompleted };
}
