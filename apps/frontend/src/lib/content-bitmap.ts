import { CanvasTexture, LinearFilter, SRGBColorSpace } from "three";
import { resolveContentFontHeight } from "@/lib/preview-3d";
import { computeFittedTextLayout } from "@/lib/text-texture";
import type { OutputContent, OutputContentPlacement } from "@/types/api";

export type ContentBitmapRequest =
  | {
      kind: "text";
      text: string;
      color: string;
      fontPx: number;
      widthPx: number;
      heightPx: number;
    }
  | {
      kind: "image";
      imageUrl: string;
      focalPoint: { x: number; y: number };
      widthPx: number;
      heightPx: number;
    };

export type ContentBitmapStatus = "ready" | "empty" | "error";

export interface ContentBitmapAsset {
  canvas: HTMLCanvasElement | null;
  status: ContentBitmapStatus;
}

const MAX_CACHE_ENTRIES = 64;
const canvasCache = new Map<string, Promise<ContentBitmapAsset>>();
const dataUrlCache = new Map<
  string,
  Promise<{ dataUrl: string | null; status: ContentBitmapStatus }>
>();
export const CONTENT_BITMAP_PIXELS_PER_WORLD_UNIT = 48;

export function contentBitmapKey(request: ContentBitmapRequest) {
  return request.kind === "text"
    ? [
        request.kind,
        request.text,
        request.color,
        request.fontPx,
        request.widthPx,
        request.heightPx,
      ].join("|")
    : [
        request.kind,
        request.imageUrl,
        request.focalPoint.x,
        request.focalPoint.y,
        request.widthPx,
        request.heightPx,
      ].join("|");
}

export function loadContentPreviewDataUrl(request: ContentBitmapRequest) {
  const key = contentBitmapKey(request);
  const cached = dataUrlCache.get(key);
  if (cached) return cached;

  const next = loadContentBitmapCanvas(request).then(({ canvas, status }) => ({
    dataUrl: canvas?.toDataURL("image/png") ?? null,
    status,
  }));
  dataUrlCache.set(key, next);
  trimPromiseCache(dataUrlCache);
  return next;
}

export function loadContentBitmapTexture(request: ContentBitmapRequest) {
  return loadContentBitmapCanvas(request).then(({ canvas, status }) => {
    if (!canvas) return null;

    const texture = new CanvasTexture(canvas);
    texture.colorSpace = SRGBColorSpace;
    texture.flipY = false;
    texture.minFilter = LinearFilter;
    texture.magFilter = LinearFilter;
    texture.needsUpdate = true;

    return { texture, status };
  });
}

export function loadContentBitmapCanvas(request: ContentBitmapRequest) {
  const key = contentBitmapKey(request);
  const cached = canvasCache.get(key);
  if (cached) return cached;

  const next =
    request.kind === "text"
      ? Promise.resolve(drawTextBitmap(request))
      : drawImageBitmap(request);

  canvasCache.set(key, next);
  trimPromiseCache(canvasCache);
  return next;
}

function drawTextBitmap(
  request: Extract<ContentBitmapRequest, { kind: "text" }>,
) {
  if (typeof document === "undefined") {
    return { canvas: null, status: "error" as const };
  }

  const canvas = document.createElement("canvas");
  canvas.width = request.widthPx;
  canvas.height = request.heightPx;

  const context = canvas.getContext("2d");
  if (!context) return { canvas: null, status: "error" as const };

  context.clearRect(0, 0, canvas.width, canvas.height);

  const layout = computeFittedTextLayout(
    request.text,
    request.widthPx,
    request.heightPx,
    request.fontPx,
    (fontPx, value) => {
      context.font = `600 ${fontPx}px "Helvetica Neue", Arial, sans-serif`;
      return context.measureText(value).width;
    },
  );

  context.save();
  context.beginPath();
  context.rect(
    layout.padding,
    layout.padding,
    canvas.width - layout.padding * 2,
    canvas.height - layout.padding * 2,
  );
  context.clip();
  context.fillStyle = request.color;
  context.font = `600 ${layout.fontPx}px "Helvetica Neue", Arial, sans-serif`;
  context.textAlign = "center";
  context.textBaseline = "middle";

  const blockHeight = layout.lines.length * layout.lineHeight;
  let y = (canvas.height - blockHeight) / 2 + layout.lineHeight / 2;

  for (const line of layout.lines) {
    context.fillText(
      line,
      canvas.width / 2,
      y,
      canvas.width - layout.padding * 2,
    );
    y += layout.lineHeight;
  }

  context.restore();

  return { canvas, status: "ready" as const };
}

function drawImageBitmap(
  request: Extract<ContentBitmapRequest, { kind: "image" }>,
) {
  if (typeof document === "undefined") {
    return Promise.resolve({ canvas: null, status: "error" as const });
  }

  if (!request.imageUrl.trim()) {
    return Promise.resolve({
      canvas: drawImageFallback(request.widthPx, request.heightPx, "empty"),
      status: "empty" as const,
    });
  }

  return new Promise<ContentBitmapAsset>((resolve) => {
    const image = new Image();
    image.crossOrigin = "anonymous";
    image.decoding = "async";

    image.onload = () => {
      const canvas = document.createElement("canvas");
      canvas.width = request.widthPx;
      canvas.height = request.heightPx;

      const context = canvas.getContext("2d");
      if (!context) {
        resolve({ canvas: null, status: "error" });
        return;
      }

      drawCoverImage(
        context,
        image,
        canvas.width,
        canvas.height,
        request.focalPoint,
      );
      resolve({ canvas, status: "ready" });
    };

    image.onerror = () => {
      resolve({
        canvas: drawImageFallback(request.widthPx, request.heightPx, "error"),
        status: "error",
      });
    };

    image.src = request.imageUrl;
  });
}

function drawCoverImage(
  context: CanvasRenderingContext2D,
  image: HTMLImageElement,
  targetWidth: number,
  targetHeight: number,
  focalPoint: { x: number; y: number },
) {
  context.clearRect(0, 0, targetWidth, targetHeight);

  const imageRatio = image.naturalWidth / Math.max(image.naturalHeight, 1);
  const targetRatio = targetWidth / Math.max(targetHeight, 1);

  let sourceWidth = image.naturalWidth;
  let sourceHeight = image.naturalHeight;
  let sourceX = 0;
  let sourceY = 0;

  if (imageRatio > targetRatio) {
    sourceWidth = image.naturalHeight * targetRatio;
    const focusX = clamp01(focalPoint.x / 100) * image.naturalWidth;
    sourceX = clamp(
      focusX - sourceWidth / 2,
      0,
      image.naturalWidth - sourceWidth,
    );
  } else {
    sourceHeight = image.naturalWidth / targetRatio;
    const focusY = clamp01(focalPoint.y / 100) * image.naturalHeight;
    sourceY = clamp(
      focusY - sourceHeight / 2,
      0,
      image.naturalHeight - sourceHeight,
    );
  }

  context.drawImage(
    image,
    sourceX,
    sourceY,
    sourceWidth,
    sourceHeight,
    0,
    0,
    targetWidth,
    targetHeight,
  );
}

function drawImageFallback(
  widthPx: number,
  heightPx: number,
  status: Exclude<ContentBitmapStatus, "ready">,
) {
  if (typeof document === "undefined") return null;

  const canvas = document.createElement("canvas");
  canvas.width = widthPx;
  canvas.height = heightPx;

  const context = canvas.getContext("2d");
  if (!context) return null;

  context.fillStyle =
    status === "error"
      ? "rgba(252,165,165,0.24)"
      : "rgba(203,213,225,0.42)";
  context.fillRect(0, 0, canvas.width, canvas.height);

  context.strokeStyle =
    status === "error" ? "rgba(185,28,28,0.52)" : "rgba(71,85,105,0.42)";
  context.setLineDash([14, 10]);
  context.lineWidth = Math.max(
    2,
    Math.round(Math.min(widthPx, heightPx) * 0.02),
  );
  context.strokeRect(
    context.lineWidth,
    context.lineWidth,
    canvas.width - context.lineWidth * 2,
    canvas.height - context.lineWidth * 2,
  );

  context.setLineDash([]);
  context.fillStyle = status === "error" ? "#991b1b" : "#475569";
  context.textAlign = "center";
  context.textBaseline = "middle";

  const headlineSize = Math.max(
    18,
    Math.round(Math.min(widthPx, heightPx) * 0.11),
  );
  const detailSize = Math.max(12, Math.round(headlineSize * 0.48));

  context.font = `700 ${headlineSize}px "Helvetica Neue", Arial, sans-serif`;
  context.fillText(
    status === "error" ? "Image unavailable" : "Add image URL",
    canvas.width / 2,
    canvas.height / 2 - headlineSize * 0.3,
    canvas.width * 0.78,
  );

  context.font = `500 ${detailSize}px "Helvetica Neue", Arial, sans-serif`;
  context.fillStyle = status === "error" ? "#7f1d1d" : "#64748b";
  context.fillText(
    status === "error"
      ? "Check the URL or CORS policy"
      : "Paste a direct image link",
    canvas.width / 2,
    canvas.height / 2 + detailSize * 1.8,
    canvas.width * 0.82,
  );

  return canvas;
}

function trimPromiseCache<T>(cache: Map<string, Promise<T>>) {
  while (cache.size > MAX_CACHE_ENTRIES) {
    const oldestKey = cache.keys().next().value;
    if (!oldestKey) return;
    cache.delete(oldestKey);
  }
}

export function buildContentBitmapRequest(
  content: OutputContent,
  width: number,
  height: number,
  fontPx: number,
) {
  return content.type === "text"
    ? {
        kind: "text" as const,
        text: content.text,
        color: content.color,
        fontPx,
        widthPx: Math.max(256, Math.round(width)),
        heightPx: Math.max(256, Math.round(height)),
      }
    : {
        kind: "image" as const,
        imageUrl: content.image_url,
        focalPoint: content.focal_point,
        widthPx: Math.max(256, Math.round(width)),
        heightPx: Math.max(256, Math.round(height)),
      };
}

export function buildPlacementBitmapRequest(
  content: OutputContentPlacement,
  widthWorld: number,
  heightWorld: number,
  panelHeight: number,
) {
  const fontWorldHeight =
    content.content.type === "text"
      ? resolveContentFontHeight(
          panelHeight,
          Math.max(heightWorld, 1),
          content.content.font_size,
        )
      : 24;

  return buildContentBitmapRequest(
    content.content,
    Math.max(
      128,
      Math.round(widthWorld * CONTENT_BITMAP_PIXELS_PER_WORLD_UNIT),
    ),
    Math.max(
      128,
      Math.round(heightWorld * CONTENT_BITMAP_PIXELS_PER_WORLD_UNIT),
    ),
    Math.max(
      24,
      Math.round(fontWorldHeight * CONTENT_BITMAP_PIXELS_PER_WORLD_UNIT),
    ),
  );
}

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function clamp01(value: number) {
  return clamp(value, 0, 1);
}
