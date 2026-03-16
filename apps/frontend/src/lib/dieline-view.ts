import { pathBounds } from '@/lib/geometry'
import type { Drawing2DResult, Path2D, SurfaceFrame2D, Vec2 } from '@/types/api'

export interface DielineContentLayout {
  content: Drawing2DResult['contents'][number]
  x: number
  y: number
  w: number
  h: number
  baseAngleRad: number
  anchorBounds: ReturnType<typeof pathBounds>
  clipPath: Path2D
  clipId: string
}

export function computeDielineBounds(result: Drawing2DResult | null) {
  if (!result || result.linework.length === 0) {
    return { minX: 0, minY: 0, maxX: 100, maxY: 100 }
  }

  return result.linework.reduce(
    (acc, linework) => {
      const next = pathBounds(linework.path)
      return {
        minX: Math.min(acc.minX, next.minX),
        minY: Math.min(acc.minY, next.minY),
        maxX: Math.max(acc.maxX, next.maxX),
        maxY: Math.max(acc.maxY, next.maxY),
      }
    },
    pathBounds(result.linework[0].path),
  )
}

export function computePanelRects(result: Drawing2DResult | null) {
  if (!result) return []

  return result.linework
    .filter((linework) => linework.role === 'cut' && linework.path.closed)
    .map((linework, index) => ({ panelId: index, path: linework.path, ...pathBounds(linework.path) }))
}

export function computeContentLayouts(result: Drawing2DResult | null, clipIdPrefix: string): DielineContentLayout[] {
  if (!result) return []

  const panelRects = computePanelRects(result)
  return result.contents.flatMap((content) => {
    const anchorPath = content.clip_path ?? panelRects.find((panel) => panel.panelId === content.panel_id)?.path
    if (!anchorPath) return []

    const anchorBounds = pathBounds(anchorPath)
    const frame =
      content.surface_frame ??
      {
        origin: { x: anchorBounds.minX, y: anchorBounds.minY },
        u_axis: { x: anchorBounds.maxX - anchorBounds.minX, y: 0 },
        v_axis: { x: 0, y: anchorBounds.maxY - anchorBounds.minY },
      }

    const projected = projectContentRect(frame, content.transform.position, content.transform.size)

    return [
      {
        content,
        x: projected.origin.x,
        y: projected.origin.y,
        w: projected.size.x,
        h: projected.size.y,
        baseAngleRad: projected.baseAngleRad,
        anchorBounds,
        clipPath: anchorPath,
        clipId: `${clipIdPrefix}-content-${content.id}`,
      },
    ]
  })
}

function projectContentRect(frame: SurfaceFrame2D, position: Vec2, size: Vec2) {
  const u_scale = position.x / 100
  const v_scale = position.y / 100
  const width_scale = size.x / 100
  const height_scale = size.y / 100

  const origin = {
    x: frame.origin.x + frame.u_axis.x * u_scale + frame.v_axis.x * v_scale,
    y: frame.origin.y + frame.u_axis.y * u_scale + frame.v_axis.y * v_scale,
  }
  const width_vector = {
    x: frame.u_axis.x * width_scale,
    y: frame.u_axis.y * width_scale,
  }
  const height_vector = {
    x: frame.v_axis.x * height_scale,
    y: frame.v_axis.y * height_scale,
  }

  return {
    origin,
    size: {
      x: Math.hypot(width_vector.x, width_vector.y),
      y: Math.hypot(height_vector.x, height_vector.y),
    },
    baseAngleRad: Math.atan2(frame.u_axis.y, frame.u_axis.x),
  }
}
