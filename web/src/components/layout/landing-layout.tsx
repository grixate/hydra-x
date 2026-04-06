import { ProjectRail } from "./project-rail";

export function LandingLayout() {
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
