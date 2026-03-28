import { Card, CardContent } from "@/components/ui/card";

export function StubPage({ title }: { title: string }) {
  return (
    <div className="p-6">
      <h1 className="font-display text-xl font-semibold">{title}</h1>
      <Card className="mt-6">
        <CardContent className="flex flex-col items-center justify-center py-16 text-center">
          <p className="text-lg font-semibold text-[var(--ink-soft)]">Coming soon</p>
          <p className="mt-1 text-sm text-[var(--ink-soft)]">
            The {title.toLowerCase()} view is under construction.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
