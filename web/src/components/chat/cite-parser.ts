// Library spec §6.3 — parse inline `<cite node_type="..." node_id="...">label</cite>`
// tags out of an assistant message's plain content. Returns an interleaved
// list of text and citation segments so MessageBubble can render real
// CitationBadge buttons that fire `GraphCommand.focus` on the cited node.

import type { Citation } from "@/types";

export type ContentPart =
  | { kind: "text"; text: string }
  | { kind: "cite"; citation: Citation; index: number; label: string };

const CITE_RE = /<cite\s+([^>]*?)>([\s\S]*?)<\/cite>/gi;
const ATTR_RE = /(\w+)\s*=\s*"([^"]*)"/g;

function parseAttrs(raw: string): Record<string, string> {
  const out: Record<string, string> = {};
  let m: RegExpExecArray | null;
  while ((m = ATTR_RE.exec(raw)) !== null) {
    out[m[1].toLowerCase()] = m[2];
  }
  return out;
}

export function parseContentWithCites(content: string): {
  parts: ContentPart[];
  citations: Citation[];
} {
  const parts: ContentPart[] = [];
  const citations: Citation[] = [];

  if (!content) {
    return { parts, citations };
  }

  let lastIndex = 0;
  let match: RegExpExecArray | null;

  // Reset regex state since CITE_RE has the /g flag.
  CITE_RE.lastIndex = 0;

  while ((match = CITE_RE.exec(content)) !== null) {
    const [full, attrsRaw, inner] = match;
    const start = match.index;

    if (start > lastIndex) {
      parts.push({ kind: "text", text: content.slice(lastIndex, start) });
    }

    const attrs = parseAttrs(attrsRaw);
    const nodeId = Number(attrs.node_id);
    const nodeType = attrs.node_type;
    const label = (inner || "").trim();

    if (Number.isFinite(nodeId) && nodeType) {
      const citation: Citation = {
        node_type: nodeType,
        node_id: nodeId,
        label: label || `${nodeType} #${nodeId}`,
        quote: label,
      };
      const index = citations.length + 1;
      citations.push(citation);
      parts.push({ kind: "cite", citation, index, label: citation.label ?? "" });
    } else {
      // Malformed — keep the literal text rather than dropping it.
      parts.push({ kind: "text", text: full });
    }

    lastIndex = start + full.length;
  }

  if (lastIndex < content.length) {
    parts.push({ kind: "text", text: content.slice(lastIndex) });
  }

  return { parts, citations };
}
