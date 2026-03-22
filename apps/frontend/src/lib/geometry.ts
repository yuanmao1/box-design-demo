import { Shape, Vector2, CubicBezierCurve, EllipseCurve } from 'three'
import type { Path2D, PathSeg } from '@/types/api'

function lineEnd(seg: PathSeg): Vector2 {
  switch (seg.kind) {
    case 'Line':
      return new Vector2(seg.to.x, seg.to.y)
    case 'Bezier':
      return new Vector2(seg.p3.x, seg.p3.y)
    case 'Arc': {
      return new Vector2(
        seg.center.x + seg.radius * Math.cos(seg.endAngle),
        seg.center.y + seg.radius * Math.sin(seg.endAngle),
      )
    }
  }
}

function lineStart(seg: PathSeg): Vector2 {
  switch (seg.kind) {
    case 'Line':
      return new Vector2(seg.from.x, seg.from.y)
    case 'Bezier':
      return new Vector2(seg.p0.x, seg.p0.y)
    case 'Arc': {
      return new Vector2(
        seg.center.x + seg.radius * Math.cos(seg.startAngle),
        seg.center.y + seg.radius * Math.sin(seg.startAngle),
      )
    }
  }
}

export function pathToSvgD(path: Path2D) {
  if (path.segments.length === 0) return ''

  const commands: string[] = []
  const first = lineStart(path.segments[0])
  commands.push(`M ${first.x} ${first.y}`)

  for (const seg of path.segments) {
    if (seg.kind === 'Line') {
      commands.push(`L ${seg.to.x} ${seg.to.y}`)
    } else if (seg.kind === 'Bezier') {
      commands.push(`C ${seg.p1.x} ${seg.p1.y} ${seg.p2.x} ${seg.p2.y} ${seg.p3.x} ${seg.p3.y}`)
    } else {
      const points = sampleArcSegment(seg, 24)
      for (const point of points) {
        commands.push(`L ${point.x} ${point.y}`)
      }
    }
  }

  if (path.closed) commands.push('Z')
  return commands.join(' ')
}

export function pathBounds(path: Path2D) {
  const points = samplePath(path)
  if (points.length === 0) return { minX: 0, minY: 0, maxX: 1, maxY: 1 }

  return points.reduce(
    (acc, point) => ({
      minX: Math.min(acc.minX, point.x),
      minY: Math.min(acc.minY, point.y),
      maxX: Math.max(acc.maxX, point.x),
      maxY: Math.max(acc.maxY, point.y),
    }),
    {
      minX: points[0].x,
      minY: points[0].y,
      maxX: points[0].x,
      maxY: points[0].y,
    },
  )
}

export function samplePath(path: Path2D, arcSegments = 24, omitSegmentIndex?: number | null) {
  const points: Vector2[] = []
  for (const [index, seg] of path.segments.entries()) {
    if (omitSegmentIndex != null && index === omitSegmentIndex) continue
    if (seg.kind === 'Line') {
      if (points.length === 0) points.push(new Vector2(seg.from.x, seg.from.y))
      points.push(new Vector2(seg.to.x, seg.to.y))
    } else if (seg.kind === 'Bezier') {
      const curve = new CubicBezierCurve(
        new Vector2(seg.p0.x, seg.p0.y),
        new Vector2(seg.p1.x, seg.p1.y),
        new Vector2(seg.p2.x, seg.p2.y),
        new Vector2(seg.p3.x, seg.p3.y),
      )
      points.push(...curve.getPoints(arcSegments))
    } else {
      points.push(...sampleArcSegment(seg, arcSegments, points.length > 0))
    }
  }
  return points
}

function sampleArcSegment(seg: Extract<PathSeg, { kind: 'Arc' }>, segments: number, skipFirstPoint = true) {
  const fullTurn = Math.PI * 2
  const sweep = seg.clockwise
    ? -mod(seg.startAngle - seg.endAngle, fullTurn)
    : mod(seg.endAngle - seg.startAngle, fullTurn)

  const points: Vector2[] = []
  for (let step = 0; step <= segments; step += 1) {
    if (skipFirstPoint && step === 0) continue
    const t = step / segments
    const angle = seg.startAngle + sweep * t
    points.push(
      new Vector2(
        seg.center.x + seg.radius * Math.cos(angle),
        seg.center.y + seg.radius * Math.sin(angle),
      ),
    )
  }
  return points
}

function mod(value: number, divisor: number) {
  return ((value % divisor) + divisor) % divisor
}

export function pathToShape(path: Path2D) {
  const shape = new Shape()
  if (path.segments.length === 0) return shape

  const first = lineStart(path.segments[0])
  shape.moveTo(first.x, first.y)

  for (const seg of path.segments) {
    if (seg.kind === 'Line') {
      shape.lineTo(seg.to.x, seg.to.y)
    } else if (seg.kind === 'Bezier') {
      shape.bezierCurveTo(seg.p1.x, seg.p1.y, seg.p2.x, seg.p2.y, seg.p3.x, seg.p3.y)
    } else {
      shape.absarc(seg.center.x, seg.center.y, seg.radius, seg.startAngle, seg.endAngle, !seg.clockwise)
    }
  }

  if (path.closed) {
    shape.closePath()
  }
  return shape
}
