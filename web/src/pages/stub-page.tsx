import { Card, CardContent } from "@/components/ui/card";

export function StubPage({ title }: { title: string }) {
  return (
    <div className="p-6">
      <h1 className="text-xl font-semibold">{title}</h1>
      <Card className="mt-6">
        <CardContent className="flex flex-col items-center justify-center py-16 text-center">
          <p className="text-lg font-semibold text-muted-foreground">Coming soon</p>
          <p className="mt-1 text-sm text-muted-foreground">
            The {title.toLowerCase()} view is under construction.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
