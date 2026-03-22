import {
  Box3,
  BufferGeometry,
  Float32BufferAttribute,
  Matrix4,
  Quaternion,
  Vector3,
} from "three";
import { pathBounds, samplePath } from "@/lib/geometry";
import type {
  OutputContentPlacement,
  Path2D,
  Preview3DNode,
  Preview3DResult,
  PreviewTransform3D,
  SurfaceFrame2D,
  Vec2,
  Vec3,
} from "@/types/api";

const EPSILON = 1e-6;
const PANEL_TEXTURE_PIXELS_PER_UNIT = 10;
const PANEL_TEXTURE_MIN = 256;
const PANEL_TEXTURE_MAX = 2048;

export interface PreviewSceneNode {
  index: number;
  node: Preview3DNode;
  contents: OutputContentPlacement[];
  worldMatrix: Matrix4;
  panelBounds: ReturnType<typeof pathBounds> | null;
  outlinePoints: [number, number, number][];
}

export interface PreviewSceneData {
  center: Vec3;
  radius: number;
  nodes: PreviewSceneNode[];
  thickness: number;
}

export function buildPreviewSceneData(result: Preview3DResult | null) {
  if (!result) return null;

  const contentsByPanel = new Map<number, OutputContentPlacement[]>();
  for (const content of result.contents) {
    const siblings = contentsByPanel.get(content.panel_id) ?? [];
    siblings.push(content);
    contentsByPanel.set(content.panel_id, siblings);
  }

  const localMatrices = result.nodes.map((node) =>
    matrixFromPreviewTransform(node.transform),
  );
  const worldMatrices = result.nodes.map(() => new Matrix4());
  const resolved = result.nodes.map(() => false);

  const resolveWorldMatrix = (index: number): Matrix4 => {
    if (resolved[index]) return worldMatrices[index];

    const node = result.nodes[index];
    if (node.parent_index == null) {
      worldMatrices[index].copy(localMatrices[index]);
    } else {
      worldMatrices[index]
        .copy(resolveWorldMatrix(node.parent_index))
        .multiply(localMatrices[index]);
    }

    resolved[index] = true;
    return worldMatrices[index];
  };

  const worldBounds = new Box3();
  const worldPoints: Vector3[] = [];

  const nodes = result.nodes.map((node, index) => {
    const worldMatrix = resolveWorldMatrix(index).clone();
    const boundaryPoints = node.boundary
      ? samplePath(node.boundary, 32).map((point) =>
          new Vector3(point.x, point.y, 0).applyMatrix4(worldMatrix),
        )
      : [];

    for (const point of boundaryPoints) {
      worldBounds.expandByPoint(point);
      worldPoints.push(point);
    }

    return {
      index,
      node,
      contents:
        node.panel_id == null ? [] : (contentsByPanel.get(node.panel_id) ?? []),
      worldMatrix,
      panelBounds: safePanelBounds(node),
      outlinePoints: node.boundary
        ? samplePath(node.boundary, 36).map(
            (point) =>
              [
                point.x,
                point.y,
                (result.thickness ?? 0) > 0 ? 0.1 : 0.45,
              ] as [number, number, number],
          )
        : [],
    } satisfies PreviewSceneNode;
  });

  const centerVector =
    worldPoints.length > 0
      ? worldBounds.getCenter(new Vector3())
      : new Vector3(0, 0, 0);
  const radius =
    worldPoints.length > 0
      ? worldPoints.reduce(
          (maxRadius, point) =>
            Math.max(maxRadius, point.distanceTo(centerVector)),
          0,
        )
      : 60;

  return {
    center: { x: centerVector.x, y: centerVector.y, z: centerVector.z },
    radius: Math.max(radius, 8),
    nodes,
    thickness: result.thickness ?? 0,
  } satisfies PreviewSceneData;
}

export function filterPanelContents(
  contents: OutputContentPlacement[],
  panelId: number | null,
) {
  return contents.filter((content) => content.panel_id === panelId);
}

export function projectPanelContent(
  bounds: { minX: number; minY: number; maxX: number; maxY: number },
  content: OutputContentPlacement,
  surfaceFrame?: SurfaceFrame2D | null,
) {
  const frame =
    surfaceFrame ??
    content.surface_frame ??
    fallbackSurfaceFrameFromBounds(bounds);
  const quad = projectContentQuad(content, frame);
  const xs = quad.map((point) => point.x);
  const ys = quad.map((point) => point.y);

  return {
    x: (Math.min(...xs) + Math.max(...xs)) / 2,
    y: (Math.min(...ys) + Math.max(...ys)) / 2,
    width: Math.max(1, averageEdgeLength(quad[0], quad[1], quad[2], quad[3])),
    height: Math.max(
      1,
      averageEdgeLength(quad[0], quad[3], quad[1], quad[2]),
    ),
    baseAngleRad: Math.atan2(quad[1].y - quad[0].y, quad[1].x - quad[0].x),
  };
}

export function resolveContentFontHeight(
  panelHeight: number,
  contentHeight: number,
  fontPercent: number,
) {
  const target = (fontPercent / 100) * panelHeight;
  return Math.max(1, Math.min(contentHeight * 0.82, target));
}

export function safePanelBounds(node: Preview3DNode) {
  return node.boundary ? pathBounds(node.boundary) : null;
}

export function fallbackSurfaceFrame(path: Path2D) {
  return fallbackSurfaceFrameFromBounds(pathBounds(path));
}

export function fallbackSurfaceFrameFromBounds(bounds: {
  minX: number;
  minY: number;
  maxX: number;
  maxY: number;
}): SurfaceFrame2D {
  return {
    origin: { x: bounds.minX, y: bounds.minY },
    u_axis: { x: bounds.maxX - bounds.minX, y: 0 },
    v_axis: { x: 0, y: bounds.maxY - bounds.minY },
  };
}

export function frameBasis(frame: SurfaceFrame2D) {
  return {
    uLength: Math.max(Math.hypot(frame.u_axis.x, frame.u_axis.y), 1),
    vLength: Math.max(Math.hypot(frame.v_axis.x, frame.v_axis.y), 1),
  };
}

export function projectContentQuad(
  content: OutputContentPlacement,
  fallbackFrame: SurfaceFrame2D,
) {
  const frame = content.surface_frame ?? fallbackFrame;
  const basis = frameBasis(frame);

  const position =
    content.transform.space === "panel_local"
      ? {
          x: content.transform.position.x / basis.uLength,
          y: content.transform.position.y / basis.vLength,
        }
      : {
          x: content.transform.position.x / 100,
          y: content.transform.position.y / 100,
        };

  const size =
    content.transform.space === "panel_local"
      ? {
          x: content.transform.size.x / basis.uLength,
          y: content.transform.size.y / basis.vLength,
        }
      : {
          x: content.transform.size.x / 100,
          y: content.transform.size.y / 100,
        };

  const center = {
    x: position.x + size.x / 2,
    y: position.y + size.y / 2,
  };

  const localCorners = [
    { x: position.x, y: position.y },
    { x: position.x + size.x, y: position.y },
    { x: position.x + size.x, y: position.y + size.y },
    { x: position.x, y: position.y + size.y },
  ].map((point) =>
    rotateAround(point, center, content.transform.rotation_rad),
  );

  return localCorners.map((point) => projectSurfacePoint(frame, point));
}

export function projectSurfacePoint(frame: SurfaceFrame2D, point: Vec2) {
  return {
    x: frame.origin.x + frame.u_axis.x * point.x + frame.v_axis.x * point.y,
    y: frame.origin.y + frame.u_axis.y * point.x + frame.v_axis.y * point.y,
  };
}

export function unprojectSurfacePoint(frame: SurfaceFrame2D, point: Vec2) {
  const det = frame.u_axis.x * frame.v_axis.y - frame.u_axis.y * frame.v_axis.x;
  if (Math.abs(det) <= EPSILON) {
    return { x: 0, y: 0 };
  }

  const dx = point.x - frame.origin.x;
  const dy = point.y - frame.origin.y;

  return {
    x: (dx * frame.v_axis.y - dy * frame.v_axis.x) / det,
    y: (dy * frame.u_axis.x - dx * frame.u_axis.y) / det,
  };
}

export function applySurfaceFrameUv(
  geometry: BufferGeometry,
  frame: SurfaceFrame2D,
) {
  const positions = geometry.getAttribute("position");
  const uv = new Float32Array(positions.count * 2);

  for (let index = 0; index < positions.count; index += 1) {
    const projected = unprojectSurfacePoint(frame, {
      x: positions.getX(index),
      y: positions.getY(index),
    });

    uv[index * 2] = projected.x;
    uv[index * 2 + 1] = 1 - projected.y;
  }

  geometry.setAttribute("uv", new Float32BufferAttribute(uv, 2));
  geometry.computeVertexNormals();
}

export function applyExtrudedUv(
  geometry: BufferGeometry,
  frame: SurfaceFrame2D,
) {
  const positions = geometry.getAttribute("position");
  geometry.computeVertexNormals();
  const normals = geometry.getAttribute("normal");
  const uv = new Float32Array(positions.count * 2);

  for (let i = 0; i < positions.count; i++) {
    const nz = normals ? normals.getZ(i) : 0;
    if (Math.abs(nz) > 0.5) {
      // Cap face (front or back): project UV via surface frame
      const projected = unprojectSurfacePoint(frame, {
        x: positions.getX(i),
        y: positions.getY(i),
      });
      uv[i * 2] = projected.x;
      uv[i * 2 + 1] = 1 - projected.y;
    } else {
      // Side face: no texture needed
      uv[i * 2] = 0;
      uv[i * 2 + 1] = 0;
    }
  }

  geometry.setAttribute("uv", new Float32BufferAttribute(uv, 2));
}

export function computePanelTextureSize(frame: SurfaceFrame2D) {
  const basis = frameBasis(frame);
  return {
    width: clampTextureSize(basis.uLength * PANEL_TEXTURE_PIXELS_PER_UNIT),
    height: clampTextureSize(basis.vLength * PANEL_TEXTURE_PIXELS_PER_UNIT),
  };
}

export function matrixFromPreviewTransform(transform: PreviewTransform3D) {
  const axis = new Vector3(
    transform.rotation_axis.x,
    transform.rotation_axis.y,
    transform.rotation_axis.z,
  );
  const quaternion =
    axis.lengthSq() <= EPSILON
      ? new Quaternion()
      : new Quaternion().setFromAxisAngle(
          axis.normalize(),
          transform.rotation_rad,
        );

  return new Matrix4()
    .makeTranslation(
      transform.translation.x,
      transform.translation.y,
      transform.translation.z,
    )
    .multiply(
      new Matrix4().makeTranslation(
        transform.rotation_origin.x,
        transform.rotation_origin.y,
        transform.rotation_origin.z,
      ),
    )
    .multiply(new Matrix4().makeRotationFromQuaternion(quaternion))
    .multiply(
      new Matrix4().makeScale(
        transform.scale.x,
        transform.scale.y,
        transform.scale.z,
      ),
    )
    .multiply(
      new Matrix4().makeTranslation(
        -transform.rotation_origin.x,
        -transform.rotation_origin.y,
        -transform.rotation_origin.z,
      ),
    );
}

function rotateAround(point: Vec2, center: Vec2, angle: number) {
  const dx = point.x - center.x;
  const dy = point.y - center.y;
  const sinAngle = Math.sin(angle);
  const cosAngle = Math.cos(angle);

  return {
    x: center.x + dx * cosAngle - dy * sinAngle,
    y: center.y + dx * sinAngle + dy * cosAngle,
  };
}

function averageEdgeLength(
  firstStart: Vec2,
  firstEnd: Vec2,
  secondStart: Vec2,
  secondEnd: Vec2,
) {
  return (
    Math.hypot(firstEnd.x - firstStart.x, firstEnd.y - firstStart.y) +
    Math.hypot(secondEnd.x - secondStart.x, secondEnd.y - secondStart.y)
  ) / 2;
}

function clampTextureSize(value: number) {
  return Math.max(
    PANEL_TEXTURE_MIN,
    Math.min(PANEL_TEXTURE_MAX, Math.round(value)),
  );
}
