/**
 * Parses agent message content for inline node, trail, and artifact references.
 *
 * Syntax:
 *   [[node:insight-42]]     → inline node card
 *   [[trail:decision-7]]    → inline trail chain
 *   [[artifact:3]]          → inline artifact section
 *
 * Malformed markers are rendered as plain text.
 */

export type ContentSegment =
  | { type: "text"; content: string }
  | { type: "node"; nodeType: string; nodeId: number }
  | { type: "trail"; nodeType: string; nodeId: number }
  | { type: "artifact"; artifactId: number };

// Matches [[node:type-id]], [[trail:type-id]], [[artifact:id]]
const REFERENCE_PATTERN = /\[\[(node|trail|artifact):([^\]]+)\]\]/g;

// Matches "type-id" like "insight-42" or "architecture_node-5"
const NODE_REF_PATTERN = /^([a-z_]+)-(\d+)$/;

export function parseMessageContent(content: string): ContentSegment[] {
  if (!content) return [];

  const segments: ContentSegment[] = [];
  let lastIndex = 0;

  // Reset regex state (global flag)
  REFERENCE_PATTERN.lastIndex = 0;

  let match: RegExpExecArray | null;
  while ((match = REFERENCE_PATTERN.exec(content)) !== null) {
    // Add preceding text segment
    if (match.index > lastIndex) {
      segments.push({ type: "text", content: content.slice(lastIndex, match.index) });
    }

    const kind = match[1] as "node" | "trail" | "artifact";
    const ref = match[2];

    const segment = parseReference(kind, ref);
    if (segment) {
      segments.push(segment);
    } else {
      // Malformed reference — render as plain text
      segments.push({ type: "text", content: match[0] });
    }

    lastIndex = match.index + match[0].length;
  }

  // Add trailing text
  if (lastIndex < content.length) {
    segments.push({ type: "text", content: content.slice(lastIndex) });
  }

  return segments;
}

function parseReference(kind: "node" | "trail" | "artifact", ref: string): ContentSegment | null {
  if (kind === "artifact") {
    const id = parseInt(ref, 10);
    if (Number.isNaN(id) || id <= 0) return null;
    return { type: "artifact", artifactId: id };
  }

  // node and trail both use type-id format
  const nodeMatch = NODE_REF_PATTERN.exec(ref);
  if (!nodeMatch) return null;

  const nodeType = nodeMatch[1];
  const nodeId = parseInt(nodeMatch[2], 10);
  if (Number.isNaN(nodeId) || nodeId <= 0) return null;

  return { type: kind, nodeType, nodeId };
}

/**
 * Check if a message contains any structured references.
 * Useful for determining whether to show "Switch to Chat" nudge.
 */
export function hasStructuredContent(content: string): boolean {
  if (!content) return false;
  REFERENCE_PATTERN.lastIndex = 0;
  return REFERENCE_PATTERN.test(content);
}

/**
 * Check if content is "long" enough to warrant the chat view.
 */
export function isLongContent(content: string, threshold = 500): boolean {
  return (content?.length ?? 0) > threshold;
}
