import { describe, expect, test } from "bun:test";
import {
  buildPreviewSceneData,
  filterPanelContents,
  frameBasis,
  projectContentQuad,
  projectPanelContent,
  resolveContentFontHeight,
  safePanelBounds,
  unprojectSurfacePoint,
} from "@/lib/preview-3d";
import type {
  OutputContentPlacement,
  Path2D,
  PathSeg,
  Preview3DResult,
} from "@/types/api";

function rectanglePath(
  x: number,
  y: number,
  width: number,
  height: number,
): Path2D {
  const segments: PathSeg[] = [
    { kind: "Line", from: { x, y }, to: { x: x + width, y } },
    {
      kind: "Line",
      from: { x: x + width, y },
      to: { x: x + width, y: y + height },
    },
    {
      kind: "Line",
      from: { x: x + width, y: y + height },
      to: { x, y: y + height },
    },
    { kind: "Line", from: { x, y: y + height }, to: { x, y } },
  ];
  return { closed: true, segments };
}

function sampleResult(): Preview3DResult {
  const left = rectanglePath(0, 0, 40, 30);
  const right = rectanglePath(40, 0, 40, 30);

  return {
    nodes: [
      {
        kind: "panel",
        parent_index: null,
        panel_id: 0,
        hinge_segment_index: null,
        boundary: left,
        surface_frame: {
          origin: { x: 0, y: 0 },
          u_axis: { x: 40, y: 0 },
          v_axis: { x: 0, y: 30 },
        },
        outside_normal: { x: 0, y: 0, z: -1 },
        transform: {
          translation: { x: 0, y: 0, z: 0 },
          rotation_origin: { x: 0, y: 0, z: 0 },
          rotation_axis: { x: 0, y: 1, z: 0 },
          rotation_rad: 0,
          scale: { x: 1, y: 1, z: 1 },
        },
      },
      {
        kind: "panel",
        parent_index: 0,
        panel_id: 1,
        hinge_segment_index: 3,
        boundary: right,
        surface_frame: {
          origin: { x: 40, y: 0 },
          u_axis: { x: 40, y: 0 },
          v_axis: { x: 0, y: 30 },
        },
        outside_normal: { x: 0, y: 0, z: -1 },
        transform: {
          translation: { x: 0, y: 0, z: 0 },
          rotation_origin: { x: 40, y: 0, z: 0 },
          rotation_axis: { x: 0, y: 1, z: 0 },
          rotation_rad: 1.57,
          scale: { x: 1, y: 1, z: 1 },
        },
      },
    ],
    contents: [
      {
        id: 9,
        panel_id: 1,
        clip_path: right,
        surface_frame: {
          origin: { x: 40, y: 0 },
          u_axis: { x: 40, y: 0 },
          v_axis: { x: 0, y: 30 },
        },
        z_index: 0,
        transform: {
          position: { x: 25, y: 10 },
          size: { x: 30, y: 40 },
          rotation_rad: 0.3,
          space: "panel_uv_percent",
        },
        content: {
          type: "text",
          text: "Front",
          color: "#0f172a",
          font_size: 16,
        },
      } satisfies OutputContentPlacement,
    ],
  };
}

describe("preview 3d helpers", () => {
  test("buildPreviewSceneData computes world matrices and fit radius", () => {
    const scene = buildPreviewSceneData(sampleResult());
    expect(scene).not.toBeNull();
    expect(scene?.nodes).toHaveLength(2);
    expect((scene?.radius ?? 0) > 20).toBe(true);
    expect((scene?.center.z ?? 1) < 1).toBe(true);
  });

  test("filterPanelContents returns items for the requested panel", () => {
    const contents = filterPanelContents(sampleResult().contents, 1);
    expect(contents).toHaveLength(1);
    expect(contents[0]?.id).toBe(9);
  });

  test("projectContentQuad follows the exported surface frame semantics", () => {
    const content = sampleResult().contents[0]!;
    const frame = sampleResult().nodes[1]!.surface_frame!;
    const quad = projectContentQuad(content, frame);

    expect(quad[0]?.x).toBeCloseTo(52.63, 2);
    expect(quad[0]?.y).toBeCloseTo(1.94, 2);
    expect(quad[2]?.x).toBeCloseTo(59.37, 2);
    expect(quad[2]?.y).toBeCloseTo(16.06, 2);
  });

  test("projectPanelContent computes a stable 3d placement summary", () => {
    const node = sampleResult().nodes[1]!;
    const bounds = safePanelBounds(node);
    expect(bounds).not.toBeNull();

    const projection = projectPanelContent(
      bounds!,
      sampleResult().contents[0]!,
      sampleResult().nodes[1]!.surface_frame,
    );
    expect(projection.x).toBeCloseTo(56, 1);
    expect(projection.y).toBeCloseTo(9, 1);
    expect(projection.width).toBeCloseTo(11.77, 1);
    expect(projection.height).toBeCloseTo(12.4, 1);
  });

  test("surface frame basis and inverse projection stay aligned", () => {
    const frame = sampleResult().nodes[1]!.surface_frame!;
    const basis = frameBasis(frame);
    expect(basis.uLength).toBe(40);
    expect(basis.vLength).toBe(30);

    const uv = unprojectSurfacePoint(frame, { x: 50, y: 12 });
    expect(uv.x).toBeCloseTo(0.25, 5);
    expect(uv.y).toBeCloseTo(0.4, 5);
  });

  test("resolveContentFontHeight uses one scale for 2d and 3d", () => {
    expect(resolveContentFontHeight(30, 7.5, 22)).toBeCloseTo(6.15, 5);
    expect(resolveContentFontHeight(30, 4, 22)).toBeCloseTo(3.28, 5);
  });
});
