import {
  buildContentBitmapRequest,
  buildPlacementBitmapRequest,
  contentBitmapKey,
  loadContentBitmapCanvas,
  type ContentBitmapStatus,
} from "@/lib/content-bitmap";
import { samplePath } from "@/lib/geometry";
import {
  computePanelTextureSize,
  fallbackSurfaceFrame,
  frameBasis,
  projectContentQuad,
  unprojectSurfacePoint,
} from "@/lib/preview-3d";
import { log3DDebug } from "@/lib/debug-3d";
import type {
  OutputContentPlacement,
  Preview3DNode,
  SurfaceFrame2D,
} from "@/types/api";
export interface PanelTextureAsset {
  canvas: HTMLCanvasElement | null;
  status: ContentBitmapStatus;
}

const panelTextureCache = new Map<string, Promise<PanelTextureAsset>>();
const MAX_CACHE_ENTRIES = 48;

export function loadPanelTextureCanvas(
  node: Preview3DNode,
  contents: OutputContentPlacement[],
) {
  const key = panelTextureKey(node, contents);
  const cached = panelTextureCache.get(key);
  if (cached) return cached;

  const next = composePanelTexture(node, contents);
  panelTextureCache.set(key, next);
  trimCache();
  return next;
}

export function panelTextureKey(
  node: Preview3DNode,
  contents: OutputContentPlacement[],
) {
  const frame = node.surface_frame;
  const framePart = frame
    ? [
        frame.origin.x,
        frame.origin.y,
        frame.u_axis.x,
        frame.u_axis.y,
        frame.v_axis.x,
        frame.v_axis.y,
      ].join(",")
    : "no-frame";

  const contentsPart = contents
    .slice()
    .sort((left, right) => left.z_index - right.z_index || left.id - right.id)
    .map((content) => {
      const frame = resolveNodeFrame(node);
      const request = frame
        ? buildContentRequestForFrame(content, frame)
        : buildContentBitmapRequest(content.content, 128, 128, 24);

      return [
        content.id,
        content.z_index,
        content.transform.space,
        content.transform.position.x,
        content.transform.position.y,
        content.transform.size.x,
        content.transform.size.y,
        content.transform.rotation_rad,
        JSON.stringify(content.clip_path),
        contentBitmapKey(request),
      ].join(":");
    })
    .join("|");

  return [
    node.panel_id ?? "panelless",
    framePart,
    JSON.stringify(node.boundary),
    contentsPart,
  ].join("::");
}

async function composePanelTexture(
  node: Preview3DNode,
  contents: OutputContentPlacement[],
): Promise<PanelTextureAsset> {
  const frame = resolveNodeFrame(node);
  if (!frame) {
    return { canvas: null, status: "error" };
  }

  const textureSize = computePanelTextureSize(frame);
  const canvas = createCanvas(textureSize.width, textureSize.height);
  const context = canvas?.getContext("2d");
  if (!canvas || !context) {
    return { canvas: null, status: "error" };
  }

  fillPanelBase(context, canvas.width, canvas.height);
  log3DDebug(`panel ${node.panel_id ?? "unknown"} compose`, {
    textureSize,
    contentCount: contents.length,
  });

  if (contents.length === 0) {
    log3DDebug(`panel ${node.panel_id ?? "unknown"} compose result`, {
      status: "empty",
      reason: "no contents",
    });
    return { canvas, status: "empty" };
  }

  const orderedContents = contents
    .slice()
    .sort((left, right) => left.z_index - right.z_index || left.id - right.id);
  let status: ContentBitmapStatus = "ready";

  for (const content of orderedContents) {
    const quad = projectContentQuad(content, frame);
    const pixelQuad = quad.map((point) => {
      const projected = unprojectSurfacePoint(frame, point);
      return {
        x: projected.x * canvas.width,
        y: projected.y * canvas.height,
      };
    });

    const widthPx = averageEdgeLength(
      pixelQuad[0],
      pixelQuad[1],
      pixelQuad[2],
      pixelQuad[3],
    );
    const heightPx = averageEdgeLength(
      pixelQuad[0],
      pixelQuad[3],
      pixelQuad[1],
      pixelQuad[2],
    );
    const request = buildContentRequestForFrame(content, frame);
    const asset = await loadContentBitmapCanvas(request);

    status = mergeStatus(status, asset.status);
    log3DDebug(`content ${content.id} bitmap`, {
      widthPx,
      heightPx,
      request,
      assetStatus: asset.status,
      hasBitmapCanvas: Boolean(asset.canvas),
    });
    if (!asset.canvas) {
      continue;
    }

    context.save();
    applyClipPath(context, content, frame, canvas.width, canvas.height);
    drawBitmapToQuad(context, asset.canvas, pixelQuad);
    context.restore();
  }

  log3DDebug(`panel ${node.panel_id ?? "unknown"} compose result`, {
    status,
    canvasSize: { width: canvas.width, height: canvas.height },
  });

  return { canvas, status };
}

function resolveNodeFrame(node: Preview3DNode) {
  if (node.surface_frame) return node.surface_frame;
  if (!node.boundary) return null;
  return fallbackSurfaceFrame(node.boundary);
}

function fillPanelBase(
  context: CanvasRenderingContext2D,
  width: number,
  height: number,
) {
  const gradient = context.createLinearGradient(0, 0, width, height);
  gradient.addColorStop(0, "#fbf7ef");
  gradient.addColorStop(1, "#eee4d5");

  context.clearRect(0, 0, width, height);
  context.fillStyle = gradient;
  context.fillRect(0, 0, width, height);

  context.strokeStyle = "rgba(120, 87, 41, 0.08)";
  context.lineWidth = Math.max(1, Math.round(Math.min(width, height) * 0.01));
  context.strokeRect(0, 0, width, height);
}

function applyClipPath(
  context: CanvasRenderingContext2D,
  content: OutputContentPlacement,
  frame: SurfaceFrame2D,
  canvasWidth: number,
  canvasHeight: number,
) {
  if (!content.clip_path) return;

  const points = samplePath(content.clip_path, 40);
  if (points.length < 3) return;

  context.beginPath();
  points.forEach((point, index) => {
    const projected = unprojectSurfacePoint(frame, {
      x: point.x,
      y: point.y,
    });
    const x = projected.x * canvasWidth;
    const y = projected.y * canvasHeight;

    if (index === 0) {
      context.moveTo(x, y);
    } else {
      context.lineTo(x, y);
    }
  });
  context.closePath();
  context.clip();
}

function drawBitmapToQuad(
  context: CanvasRenderingContext2D,
  bitmap: HTMLCanvasElement,
  quad: Array<{ x: number; y: number }>,
) {
  const [topLeft, topRight, , bottomLeft] = quad;
  context.setTransform(
    (topRight.x - topLeft.x) / Math.max(bitmap.width, 1),
    (topRight.y - topLeft.y) / Math.max(bitmap.width, 1),
    (bottomLeft.x - topLeft.x) / Math.max(bitmap.height, 1),
    (bottomLeft.y - topLeft.y) / Math.max(bitmap.height, 1),
    topLeft.x,
    topLeft.y,
  );
  context.drawImage(bitmap, 0, 0);
  context.setTransform(1, 0, 0, 1, 0, 0);
}

function averageEdgeLength(
  firstStart: { x: number; y: number },
  firstEnd: { x: number; y: number },
  secondStart: { x: number; y: number },
  secondEnd: { x: number; y: number },
) {
  return (
    Math.hypot(firstEnd.x - firstStart.x, firstEnd.y - firstStart.y) +
    Math.hypot(secondEnd.x - secondStart.x, secondEnd.y - secondStart.y)
  ) / 2;
}

function mergeStatus(
  current: ContentBitmapStatus,
  next: ContentBitmapStatus,
): ContentBitmapStatus {
  if (current === "error" || next === "error") return "error";
  if (current === "ready" || next === "ready") return "ready";
  return "empty";
}

function trimCache() {
  while (panelTextureCache.size > MAX_CACHE_ENTRIES) {
    const oldestKey = panelTextureCache.keys().next().value;
    if (!oldestKey) return;
    panelTextureCache.delete(oldestKey);
  }
}

function createCanvas(width: number, height: number) {
  if (typeof document === "undefined") return null;

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  return canvas;
}

function buildContentRequestForFrame(
  content: OutputContentPlacement,
  frame: SurfaceFrame2D,
) {
  const quad = projectContentQuad(content, frame);
  const widthWorld = averageEdgeLength(quad[0], quad[1], quad[2], quad[3]);
  const heightWorld = averageEdgeLength(quad[0], quad[3], quad[1], quad[2]);
  const panelHeight = frameBasis(frame).vLength;
  return buildPlacementBitmapRequest(content, widthWorld, heightWorld, panelHeight);
}
