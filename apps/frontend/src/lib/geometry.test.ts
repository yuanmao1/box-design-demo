import { describe, expect, test } from 'bun:test'
import { samplePath } from '@/lib/geometry'
import type { Path2D, Vec2 } from '@/types/api'

function segmentsProperlyIntersect(a0: Vec2, a1: Vec2, b0: Vec2, b1: Vec2) {
  const o1 = orientation(a0, a1, b0)
  const o2 = orientation(a0, a1, b1)
  const o3 = orientation(b0, b1, a0)
  const o4 = orientation(b0, b1, a1)

  if (Math.abs(o1) <= 1e-6 || Math.abs(o2) <= 1e-6 || Math.abs(o3) <= 1e-6 || Math.abs(o4) <= 1e-6) {
    return false
  }

  return ((o1 > 0 && o2 < 0) || (o1 < 0 && o2 > 0)) && ((o3 > 0 && o4 < 0) || (o3 < 0 && o4 > 0))
}

function orientation(a: Vec2, b: Vec2, c: Vec2) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
}

function segmentsAreAdjacent(edgeCount: number, leftIndex: number, rightIndex: number) {
  return (
    leftIndex === rightIndex ||
    leftIndex + 1 === rightIndex ||
    rightIndex + 1 === leftIndex ||
    (leftIndex === 0 && rightIndex + 1 === edgeCount) ||
    (rightIndex === 0 && leftIndex + 1 === edgeCount)
  )
}

function hasSelfIntersection(path: Path2D) {
  const points = samplePath(path, 24)
  if (points.length < 3) return false

  const vertices = points.map((point) => ({ x: point.x, y: point.y }))
  if (vertices.length > 1) {
    const first = vertices[0]
    const last = vertices[vertices.length - 1]
    if (Math.abs(first.x - last.x) <= 1e-6 && Math.abs(first.y - last.y) <= 1e-6) {
      vertices.pop()
    }
  }

  const edgeCount = vertices.length
  for (let leftIndex = 0; leftIndex < edgeCount; leftIndex += 1) {
    const leftStart = vertices[leftIndex]!
    const leftEnd = vertices[(leftIndex + 1) % edgeCount]!
    for (let rightIndex = leftIndex + 1; rightIndex < edgeCount; rightIndex += 1) {
      if (segmentsAreAdjacent(edgeCount, leftIndex, rightIndex)) continue
      const rightStart = vertices[rightIndex]!
      const rightEnd = vertices[(rightIndex + 1) % edgeCount]!
      if (segmentsProperlyIntersect(leftStart, leftEnd, rightStart, rightEnd)) return true
    }
  }

  return false
}

describe('geometry arc sampling', () => {
  test('annular sector path does not self-intersect when sampled', () => {
    const path: Path2D = {
      closed: true,
      segments: [
        { kind: 'Arc', center: { x: 0, y: 0 }, radius: 50, startAngle: 0, endAngle: Math.PI / 2, clockwise: false },
        { kind: 'Line', from: { x: 0, y: 50 }, to: { x: 0, y: 12 } },
        { kind: 'Arc', center: { x: 0, y: 0 }, radius: 12, startAngle: Math.PI / 2, endAngle: 0, clockwise: true },
        { kind: 'Line', from: { x: 12, y: 0 }, to: { x: 50, y: 0 } },
      ],
    }

    expect(hasSelfIntersection(path)).toBe(false)
  })
})
