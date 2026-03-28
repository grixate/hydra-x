import { useParams } from "react-router-dom";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

export function SettingsPage() {
  const { projectId } = useParams<{ projectId: string }>();

  return (
    <div className="p-6 space-y-6">
      <h1 className="font-display text-xl font-semibold">Settings</h1>

      <Card>
        <CardHeader><CardTitle className="text-sm">Watch Targets</CardTitle></CardHeader>
        <CardContent className="text-sm text-[var(--ink-soft)]">
          Configure competitors, keywords, and URLs to monitor. Coming soon.
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-sm">Routines</CardTitle></CardHeader>
        <CardContent className="text-sm text-[var(--ink-soft)]">
          Configure recurring agent tasks. Coming soon.
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-sm">Knowledge Library</CardTitle></CardHeader>
        <CardContent className="text-sm text-[var(--ink-soft)]">
          Manage reference material for your agents. Coming soon.
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-sm">Constraints</CardTitle></CardHeader>
        <CardContent className="text-sm text-[var(--ink-soft)]">
          Define non-negotiable project boundaries. Coming soon.
        </CardContent>
      </Card>

      <Card>
        <CardHeader><CardTitle className="text-sm">Trust Level</CardTitle></CardHeader>
        <CardContent className="text-sm text-[var(--ink-soft)]">
          Control how much autonomy your agents have. Coming soon.
        </CardContent>
      </Card>
    </div>
  );
}
