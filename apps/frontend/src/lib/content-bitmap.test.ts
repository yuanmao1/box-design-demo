import { describe, expect, test } from 'bun:test'
import { buildContentBitmapRequest, buildPlacementBitmapRequest, contentBitmapKey } from '@/lib/content-bitmap'

describe('content bitmap helpers', () => {
  test('contentBitmapKey changes with request identity', () => {
    const a = contentBitmapKey({ kind: 'text', text: 'Pack', color: '#111827', fontPx: 32, widthPx: 512, heightPx: 256 })
    const b = contentBitmapKey({ kind: 'image', imageUrl: 'https://example.com/a.png', focalPoint: { x: 50, y: 50 }, widthPx: 512, heightPx: 256 })

    expect(a).not.toBe(b)
  })

  test('buildContentBitmapRequest keeps text and image requests distinct', () => {
    const textRequest = buildContentBitmapRequest({ type: 'text', text: 'Pack', color: '#111827', font_size: 22 }, 180.4, 96.2, 84)
    const imageRequest = buildContentBitmapRequest({ type: 'image', image_url: 'https://example.com/a.png', focal_point: { x: 50, y: 50 } }, 180.4, 96.2, 84)

    expect(textRequest.kind).toBe('text')
    expect(imageRequest.kind).toBe('image')
    expect(textRequest.widthPx).toBe(256)
    expect(imageRequest.heightPx).toBe(256)
    if (imageRequest.kind === 'image') {
      expect(imageRequest.focalPoint.x).toBe(50)
      expect(imageRequest.focalPoint.y).toBe(50)
    }
  })

  test('buildPlacementBitmapRequest uses one shared scale for 2d and 3d', () => {
    const request = buildPlacementBitmapRequest(
      {
        id: 1,
        panel_id: 0,
        clip_path: null,
        surface_frame: null,
        z_index: 0,
        transform: {
          position: { x: 10, y: 10 },
          size: { x: 30, y: 40 },
          rotation_rad: 0,
          space: 'panel_uv_percent',
        },
        content: {
          type: 'text',
          text: 'Packaging',
          color: '#111827',
          font_size: 22,
        },
      },
      12,
      12,
      30,
    )

    expect(request.kind).toBe('text')
    if (request.kind === 'text') {
      expect(request.widthPx).toBe(576)
      expect(request.heightPx).toBe(576)
      expect(request.fontPx).toBe(317)
    }
  })
})
