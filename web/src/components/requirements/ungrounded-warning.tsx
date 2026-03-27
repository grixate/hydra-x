import { AlertTriangle } from "lucide-react";

export function UngroundedWarning() {
  return (
    <div className="rounded-[1.4rem] border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-950">
      <p className="inline-flex items-center gap-2 font-semibold">
        <AlertTriangle className="h-4 w-4" />
        Ungrounded requirement
      </p>
      <p className="mt-2 text-amber-900/80">
        This requirement cannot be accepted until it is linked to grounded insights with source evidence.
      </p>
    </div>
  );
}
