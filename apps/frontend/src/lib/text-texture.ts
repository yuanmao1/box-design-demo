import { CanvasTexture, LinearFilter, SRGBColorSpace } from 'three'

export interface TextTextureLayout {
  lines: string[]
  lineHeight: number
  padding: number
}

export interface TextTextureRequest {
  text: string
  color: string
  fontPx: number
  widthPx: number
  heightPx: number
}

export interface FittedTextLayout extends TextTextureLayout {
  fontPx: number
  innerWidth: number
  innerHeight: number
}

const MAX_CACHE_ENTRIES = 64
const textureCache = new Map<string, CanvasTexture>()
const dataUrlCache = new Map<string, string>()

export function computeTextLayout(
  text: string,
  maxWidth: number,
  maxHeight: number,
  fontPx: number,
  measure: (value: string) => number,
): TextTextureLayout {
  const padding = Math.max(16, Math.round(fontPx * 0.35))
  const lineHeight = Math.max(fontPx * 1.18, 20)
  const innerWidth = Math.max(8, maxWidth - padding * 2)
  const maxLines = Math.max(1, Math.floor((maxHeight - padding * 2) / lineHeight))
  const wrapped = wrapTextLines(text, innerWidth, measure)

  if (wrapped.length <= maxLines) {
    return { lines: wrapped, lineHeight, padding }
  }

  const clipped = wrapped.slice(0, maxLines)
  clipped[maxLines - 1] = fitLineWithEllipsis(clipped[maxLines - 1] ?? '', innerWidth, measure)
  return { lines: clipped, lineHeight, padding }
}

export function wrapTextLines(text: string, maxWidth: number, measure: (value: string) => number) {
  const normalized = text.replace(/\s+/g, ' ').trim()
  if (!normalized) return [' ']

  const words = normalized.split(' ')
  const lines: string[] = []
  let current = ''

  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word
    if (measure(candidate) <= maxWidth) {
      current = candidate
      continue
    }

    if (current) {
      lines.push(current)
      current = ''
    }

    if (measure(word) <= maxWidth) {
      current = word
      continue
    }

    const fragments = breakLongWord(word, maxWidth, measure)
    lines.push(...fragments.slice(0, -1))
    current = fragments[fragments.length - 1] ?? ''
  }

  if (current) {
    lines.push(current)
  }

  return lines.length ? lines : [' ']
}

export function textureCacheKey(request: TextTextureRequest) {
  return [request.text, request.color, request.fontPx, request.widthPx, request.heightPx].join('|')
}

export function getOrCreateTextTexture(request: TextTextureRequest) {
  const key = textureCacheKey(request)
  const cached = textureCache.get(key)
  if (cached) return cached

  const canvas = drawTextCanvas(request)
  if (!canvas) return null

  const texture = new CanvasTexture(canvas)
  texture.colorSpace = SRGBColorSpace
  texture.minFilter = LinearFilter
  texture.magFilter = LinearFilter
  texture.needsUpdate = true

  textureCache.set(key, texture)
  trimCache()
  return texture
}

export function getTextPreviewDataUrl(request: TextTextureRequest) {
  const key = textureCacheKey(request)
  const cached = dataUrlCache.get(key)
  if (cached) return cached

  const canvas = drawTextCanvas(request)
  if (!canvas) return null

  const dataUrl = canvas.toDataURL('image/png')
  dataUrlCache.set(key, dataUrl)
  trimDataUrlCache()
  return dataUrl
}

export function computeFittedTextLayout(
  text: string,
  widthPx: number,
  heightPx: number,
  targetFontPx: number,
  measure: (fontPx: number, value: string) => number,
): FittedTextLayout {
  let fontPx = Math.max(18, Math.min(targetFontPx, heightPx * 0.55))
  let layout = layoutForFont(text, widthPx, heightPx, fontPx, measure)

  while (fontPx > 18 && layout.lines.some((line) => line.endsWith('…'))) {
    const nextFontPx = Math.max(18, Math.round(fontPx * 0.9))
    if (nextFontPx === fontPx) break
    fontPx = nextFontPx
    layout = layoutForFont(text, widthPx, heightPx, fontPx, measure)
  }

  return {
    ...layout,
    fontPx,
    innerWidth: Math.max(8, widthPx - layout.padding * 2),
    innerHeight: Math.max(8, heightPx - layout.padding * 2),
  }
}

function trimCache() {
  while (textureCache.size > MAX_CACHE_ENTRIES) {
    const oldestKey = textureCache.keys().next().value
    if (!oldestKey) return
    const texture = textureCache.get(oldestKey)
    texture?.dispose()
    textureCache.delete(oldestKey)
  }
}

function trimDataUrlCache() {
  while (dataUrlCache.size > MAX_CACHE_ENTRIES) {
    const oldestKey = dataUrlCache.keys().next().value
    if (!oldestKey) return
    dataUrlCache.delete(oldestKey)
  }
}

function layoutForFont(
  text: string,
  widthPx: number,
  heightPx: number,
  fontPx: number,
  measure: (fontPx: number, value: string) => number,
) {
  return computeTextLayout(
    text,
    widthPx,
    heightPx,
    fontPx,
    (value) => measure(fontPx, value),
  )
}

function breakLongWord(word: string, maxWidth: number, measure: (value: string) => number) {
  const parts: string[] = []
  let current = ''

  for (const char of word) {
    const candidate = `${current}${char}`
    if (current && measure(candidate) > maxWidth) {
      parts.push(current)
      current = char
    } else {
      current = candidate
    }
  }

  if (current) parts.push(current)
  return parts.length ? parts : [word]
}

function fitLineWithEllipsis(line: string, maxWidth: number, measure: (value: string) => number) {
  if (measure(`${line}…`) <= maxWidth) return `${line}…`

  let current = line
  while (current.length > 1 && measure(`${current}…`) > maxWidth) {
    current = current.slice(0, -1)
  }
  return `${current}…`
}

function drawTextCanvas(request: TextTextureRequest) {
  if (typeof document === 'undefined') return null

  const canvas = document.createElement('canvas')
  canvas.width = request.widthPx
  canvas.height = request.heightPx

  const context = canvas.getContext('2d')
  if (!context) return null

  context.clearRect(0, 0, canvas.width, canvas.height)
  context.fillStyle = 'rgba(255,255,255,0)'
  context.fillRect(0, 0, canvas.width, canvas.height)

  const layout = computeFittedTextLayout(
    request.text,
    request.widthPx,
    request.heightPx,
    request.fontPx,
    (fontPx, value) => {
      context.font = `600 ${fontPx}px "Helvetica Neue", Arial, sans-serif`
      return context.measureText(value).width
    },
  )

  context.save()
  context.beginPath()
  context.rect(layout.padding, layout.padding, canvas.width - layout.padding * 2, canvas.height - layout.padding * 2)
  context.clip()
  context.fillStyle = request.color
  context.font = `600 ${layout.fontPx}px "Helvetica Neue", Arial, sans-serif`
  context.textAlign = 'center'
  context.textBaseline = 'middle'

  const blockHeight = layout.lines.length * layout.lineHeight
  let y = (canvas.height - blockHeight) / 2 + layout.lineHeight / 2
  for (const line of layout.lines) {
    context.fillText(line, canvas.width / 2, y, canvas.width - layout.padding * 2)
    y += layout.lineHeight
  }
  context.restore()

  return canvas
}
