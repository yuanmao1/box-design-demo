import { describe, expect, test } from 'bun:test'
import { computeTextLayout, textureCacheKey, wrapTextLines } from '@/lib/text-texture'

describe('text texture helpers', () => {
  test('wrapTextLines breaks text into multiple rows within width', () => {
    const lines = wrapTextLines('Packaging Front Panel', 90, (value) => value.length * 10)
    expect(lines).toEqual(['Packaging', 'Front', 'Panel'])
  })

  test('computeTextLayout clips overflowing lines with ellipsis', () => {
    const layout = computeTextLayout(
      'This is a long packaging title that must wrap and clip',
      140,
      68,
      18,
      (value) => value.length * 8,
    )

    expect(layout.lines.length).toBe(1)
    expect(layout.lines[0]?.endsWith('…')).toBe(true)
  })

  test('textureCacheKey changes with visual parameters', () => {
    const a = textureCacheKey({ text: 'Pack', color: '#111111', fontPx: 28, widthPx: 512, heightPx: 512 })
    const b = textureCacheKey({ text: 'Pack', color: '#111111', fontPx: 28, widthPx: 1024, heightPx: 512 })

    expect(a).not.toBe(b)
  })
})
