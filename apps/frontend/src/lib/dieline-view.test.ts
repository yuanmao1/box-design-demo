import { describe, expect, test } from 'bun:test'
import { computeContentLayouts, computeDielineBounds, computePanelRects } from '@/lib/dieline-view'
import type { Drawing2DResult, Path2D, PathSeg } from '@/types/api'

function rectanglePath(x: number, y: number, width: number, height: number): Path2D {
  const segments: PathSeg[] = [
    { kind: 'Line', from: { x, y }, to: { x: x + width, y } },
    { kind: 'Line', from: { x: x + width, y }, to: { x: x + width, y: y + height } },
    { kind: 'Line', from: { x: x + width, y: y + height }, to: { x, y: y + height } },
    { kind: 'Line', from: { x, y: y + height }, to: { x, y } },
  ]
  return { closed: true, segments }
}

function sampleDrawing(): Drawing2DResult {
  const panel = rectanglePath(0, 0, 80, 40)
  return {
    linework: [
      {
        role: 'cut',
        stroke_style: 'solid',
        path: panel,
      },
      {
        role: 'score',
        stroke_style: 'dashed',
        path: {
          closed: false,
          segments: [{ kind: 'Line', from: { x: 40, y: 0 }, to: { x: 40, y: 40 } }],
        },
      },
    ],
    contents: [
      {
        id: 11,
        panel_id: 0,
        clip_path: panel,
        surface_frame: {
          origin: { x: 0, y: 0 },
          u_axis: { x: 80, y: 0 },
          v_axis: { x: 0, y: 40 },
        },
        z_index: 0,
        transform: {
          position: { x: 10, y: 25 },
          size: { x: 50, y: 20 },
          rotation_rad: 0,
          space: 'panel_uv_percent',
        },
        content: {
          type: 'text',
          text: 'Hello',
          color: '#111827',
          font_size: 24,
        },
      },
    ],
  }
}

describe('dieline view helpers', () => {
  test('computeDielineBounds spans all linework', () => {
    const bounds = computeDielineBounds(sampleDrawing())
    expect(bounds.minX).toBe(0)
    expect(bounds.minY).toBe(0)
    expect(bounds.maxX).toBe(80)
    expect(bounds.maxY).toBe(40)
  })

  test('computePanelRects identifies closed cut paths as panels', () => {
    const panelRects = computePanelRects(sampleDrawing())
    expect(panelRects).toHaveLength(1)
    expect(panelRects[0]?.panelId).toBe(0)
    expect(panelRects[0]?.maxX).toBe(80)
  })

  test('computeContentLayouts projects content into panel space', () => {
    const layouts = computeContentLayouts(sampleDrawing(), 'test')
    expect(layouts).toHaveLength(1)
    expect(layouts[0]?.clipId).toBe('test-content-11')
    expect(layouts[0]?.x).toBe(8)
    expect(layouts[0]?.y).toBe(10)
    expect(layouts[0]?.w).toBe(40)
    expect(layouts[0]?.h).toBe(8)
  })
})
