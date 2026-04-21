const HINT_KEY = "hydra_dismissed_hints";

export function isHintDismissed(hint: string): boolean {
  try {
    const dismissed = JSON.parse(localStorage.getItem(HINT_KEY) || "{}");
    return !!dismissed[hint];
  } catch {
    return false;
  }
}

export function dismissHint(hint: string): void {
  try {
    const dismissed = JSON.parse(localStorage.getItem(HINT_KEY) || "{}");
    dismissed[hint] = true;
    localStorage.setItem(HINT_KEY, JSON.stringify(dismissed));
  } catch {
    // localStorage may be unavailable
  }
}
