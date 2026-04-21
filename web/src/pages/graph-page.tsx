import { useParams } from "react-router-dom";
import { GraphView } from "@/components/graph/graph-view";
import { OnboardingBanner } from "@/components/onboarding/onboarding-banner";

export function GraphPage() {
  const { projectId } = useParams<{ projectId: string }>();

  if (!projectId) return null;

  return (
    <div className="relative flex h-full w-full flex-col">
      <OnboardingBanner surface="graph" />
      <div className="min-h-0 flex-1">
        <GraphView projectId={Number(projectId)} />
      </div>
    </div>
  );
}
