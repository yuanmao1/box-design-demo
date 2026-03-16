import type { OutputContent, OutputContentPlacement } from '@/types/api'

export function nextContentId() {
  return crypto.getRandomValues(new Uint32Array(1))[0]
}

export function createContent(type: OutputContent['type'], panelId: number): OutputContentPlacement {
  return {
    id: nextContentId(),
    panel_id: panelId,
    transform: {
      position: { x: 15, y: 20 },
      size: { x: 35, y: 25 },
      rotation_rad: 0,
      space: 'panel_uv_percent',
    },
    clip_path: null,
    surface_frame: null,
    z_index: 0,
    content:
      type === 'text'
        ? {
            type: 'text',
            text: 'Packaging',
            color: '#0f172a',
            font_size: 22,
          }
        : {
            type: 'image',
            image_url: '',
            focal_point: { x: 50, y: 50 },
          },
  }
}

export function mergeContentPatch(
  content: OutputContentPlacement,
  patch: Partial<OutputContentPlacement>,
): OutputContentPlacement {
  return {
    ...content,
    ...patch,
    transform: patch.transform ? { ...content.transform, ...patch.transform } : content.transform,
    content: patch.content ? ({ ...content.content, ...patch.content } as OutputContent) : content.content,
  }
}

export function describeWasmError(error: string | null) {
  if (!error) return null

  switch (error) {
    case 'ContentOutOfBounds':
      return 'The edited content exceeds the target panel bounds.'
    case 'InvalidContentSize':
      return 'Content width and height must stay positive.'
    case 'UnknownPanelId':
      return 'The selected panel is not available in the current template.'
    case 'PanelRejectsContent':
      return 'This panel currently does not allow content placement.'
    default:
      return 'The latest wasm generation failed. The previews are showing the last successful result.'
  }
}
