import { Check, Copy, Download } from "lucide-react";
import { useState } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import type { Project, ProjectExport } from "@/types";

export function ExportDialog({
  open,
  project,
  exportResult,
  exporting,
  onClose,
  onExport,
}: {
  open: boolean;
  project: Project | null;
  exportResult: ProjectExport | null;
  exporting: boolean;
  onClose: () => void;
  onExport: () => Promise<void>;
}) {
  const [copiedPath, setCopiedPath] = useState<string | null>(null);

  async function handleCopy(value: string) {
    try {
      await navigator.clipboard.writeText(value);
      setCopiedPath(value);
      window.setTimeout(() => setCopiedPath((current) => (current === value ? null : current)), 1500);
    } catch (_error) {
      setCopiedPath(null);
    }
  }

  const paths = exportResult
    ? [
        { label: "Bundle directory", value: exportResult.bundle_dir },
        { label: "Markdown narrative", value: exportResult.markdown_path },
        { label: "JSON snapshot", value: exportResult.json_path },
      ]
    : [];

  return (
    <Dialog open={open} onOpenChange={(next) => !next && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Project export snapshot</DialogTitle>
          <DialogDescription>
            Generate a portable evidence package for {project?.name ?? "the active project"}.
          </DialogDescription>
        </DialogHeader>

        <div className="mt-6 space-y-5">
          <Card className="bg-[var(--paper-strong)]">
            <CardHeader className="pb-3">
              <CardTitle className="text-xl">What gets bundled</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-wrap gap-2">
              <Badge variant="neutral">Sources</Badge>
              <Badge variant="neutral">Insights</Badge>
              <Badge variant="neutral">Requirements</Badge>
              <Badge variant="neutral">Conversation transcripts</Badge>
            </CardContent>
          </Card>

          {exportResult ? (
            <div className="space-y-3">
              {paths.map((path) => (
                <Card key={path.label}>
                  <CardHeader className="pb-2">
                    <CardTitle className="text-base">{path.label}</CardTitle>
                  </CardHeader>
                  <CardContent className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                    <code className="overflow-x-auto rounded-2xl bg-[var(--paper-strong)] px-4 py-3 text-xs text-muted-foreground">
                      {path.value}
                    </code>
                    <Button
                      type="button"
                      variant="secondary"
                      size="sm"
                      onClick={() => void handleCopy(path.value)}
                    >
                      {copiedPath === path.value ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                      {copiedPath === path.value ? "Copied" : "Copy path"}
                    </Button>
                  </CardContent>
                </Card>
              ))}

              <div className="flex flex-wrap gap-2">
                <Badge variant="success">{exportResult.counts.sources} sources</Badge>
                <Badge variant="success">{exportResult.counts.insights} insights</Badge>
                <Badge variant="success">{exportResult.counts.requirements} requirements</Badge>
                <Badge variant="success">{exportResult.counts.conversations} conversations</Badge>
              </div>
            </div>
          ) : (
            <Card>
              <CardContent className="p-6 text-sm leading-7 text-muted-foreground">
                Run the export once to materialize the markdown narrative, JSON snapshot, and transcript bundle paths for this project.
              </CardContent>
            </Card>
          )}

          <div className="flex justify-end gap-3">
            <Button type="button" variant="secondary" onClick={onClose}>
              Close
            </Button>
            <Button type="button" disabled={exporting} onClick={() => void onExport()}>
              <Download className="h-4 w-4" />
              {exporting ? "Exporting..." : exportResult ? "Regenerate export" : "Generate export"}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
