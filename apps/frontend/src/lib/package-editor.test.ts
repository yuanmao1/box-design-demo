import { describe, expect, test } from 'bun:test'
import { createContent, describeWasmError, mergeContentPatch } from '@/lib/package-editor'

describe('package editor helpers', () => {
  test('createContent builds a text placement with default transform', () => {
    const content = createContent('text', 3)

    expect(content.panel_id).toBe(3)
    expect(content.content.type).toBe('text')
    expect(content.transform.space).toBe('panel_uv_percent')
    expect(content.transform.size.x).toBe(35)
    expect(content.transform.size.y).toBe(25)
  })

  test('mergeContentPatch keeps existing nested fields', () => {
    const content = createContent('text', 1)
    const merged = mergeContentPatch(content, {
      transform: {
        ...content.transform,
        position: { ...content.transform.position, x: 42 },
      },
      content: {
        type: 'text',
        text: 'Updated',
        color: '#112233',
        font_size: 30,
      },
    })

    expect(merged.transform.position.x).toBe(42)
    expect(merged.transform.position.y).toBe(content.transform.position.y)
    expect(merged.content.type).toBe('text')
    if (merged.content.type === 'text') {
      expect(merged.content.text).toBe('Updated')
      expect(merged.content.color).toBe('#112233')
      expect(merged.content.font_size).toBe(30)
    }
  })

  test('describeWasmError returns a business-readable message', () => {
    expect(describeWasmError('ContentOutOfBounds')).toContain('exceeds the target panel bounds')
    expect(describeWasmError('UnknownSomething')).toContain('latest wasm generation failed')
  })

  test('createContent builds an image placement with default focal point', () => {
    const content = createContent('image', 2)

    expect(content.content.type).toBe('image')
    if (content.content.type === 'image') {
      expect(content.content.focal_point.x).toBe(50)
      expect(content.content.focal_point.y).toBe(50)
    }
  })
})
