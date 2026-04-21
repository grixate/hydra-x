import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

const API_PREFIX = import.meta.env.VITE_API_BASE ?? "/api/v1";

async function checkAuthStatus(): Promise<{ password_configured: boolean; authenticated: boolean }> {
  const res = await fetch(`${API_PREFIX}/auth/status`, { credentials: "include" });
  const json = await res.json();
  return json.data;
}

async function login(password: string): Promise<{ success: boolean; error?: string }> {
  const res = await fetch(`${API_PREFIX}/auth/login`, {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ password }),
  });
  if (res.ok) return { success: true };
  const json = await res.json();
  return { success: false, error: json.error ?? "Login failed" };
}

export function AuthPage() {
  const navigate = useNavigate();
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [checking, setChecking] = useState(true);

  // Check if already authenticated or no password configured
  useEffect(() => {
    checkAuthStatus()
      .then((status) => {
        if (status.authenticated) {
          navigate("/", { replace: true });
        }
      })
      .catch(() => {})
      .finally(() => setChecking(false));
  }, [navigate]);

  const handleSubmit = async () => {
    if (!password.trim() || submitting) return;
    setSubmitting(true);
    setError(null);

    try {
      const result = await login(password);
      if (result.success) {
        navigate("/", { replace: true });
      } else {
        setError(
          result.error === "invalid_password"
            ? "Invalid password"
            : result.error === "rate_limited"
              ? "Too many attempts. Please try again later."
              : "Login failed",
        );
        setSubmitting(false);
      }
    } catch {
      setError("Unable to connect. Check your network and try again.");
      setSubmitting(false);
    }
  };

  if (checking) return null;

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="w-full max-w-sm space-y-8 text-center">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Hydra</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Product development with AI agents
          </p>
        </div>

        <Card>
          <CardContent className="p-5 space-y-4">
            <div>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Password"
                className="w-full rounded-md border bg-background px-3 py-2 text-sm focus:outline-none focus:ring-1 focus:ring-ring"
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    handleSubmit();
                  }
                }}
                autoFocus
              />
            </div>

            {error && (
              <p className="text-sm text-destructive">{error}</p>
            )}

            <Button
              className="w-full"
              onClick={handleSubmit}
              disabled={!password.trim() || submitting}
            >
              {submitting ? "Signing in..." : "Sign in"}
            </Button>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
