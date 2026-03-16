import { useEffect, useId, useMemo, useRef, useState, type PointerEvent as ReactPointerEvent } from 'react'
import { buildPlacementBitmapRequest, loadContentPreviewDataUrl } from '@/lib/content-bitmap'
import { pathToSvgD } from '@/lib/geometry'
import { computeContentLayouts, computeDielineBounds, computePanelRects } from '@/lib/dieline-view'
import type { GeneratedPackage, OutputContentPlacement } from '@/types/api'

const GRID_MINOR = 10
const GRID_MAJOR = 50

export function DielinePreview({
  result,
}: {
  result: GeneratedPackage['drawing_2d'] | null
}) {
  const svgRef = useRef<SVGSVGElement | null>(null)
  const clipIdPrefix = useId()
  const [camera, setCamera] = useState({ panX: 0, panY: 0, zoom: 1 })
  const dragState = useRef<{ x: number; y: number } | null>(null)

  const bounds = useMemo(() => computeDielineBounds(result), [result])
  const panelRects = useMemo(() => computePanelRects(result), [result])
  const contentLayouts = useMemo(() => computeContentLayouts(result, clipIdPrefix), [clipIdPrefix, result])

  useEffect(() => {
    setCamera({ panX: 0, panY: 0, zoom: 1 })
  }, [result])

  useEffect(() => {
    const svg = svgRef.current
    if (!svg) return

    const handleWheel = (event: WheelEvent) => {
      event.preventDefault()
      setCamera((current) => ({
        ...current,
        zoom: Math.min(8, Math.max(0.35, current.zoom * (event.deltaY > 0 ? 0.92 : 1.08))),
      }))
    }

    svg.addEventListener('wheel', handleWheel, { passive: false })
    return () => svg.removeEventListener('wheel', handleWheel)
  }, [])

  if (!result) {
    return <EmptyState label="Loading dieline from wasm export..." />
  }

  const width = bounds.maxX - bounds.minX || 1
  const height = bounds.maxY - bounds.minY || 1
  const pad = Math.max(width, height) * 0.16
  const centerX = bounds.minX + width / 2
  const centerY = bounds.minY + height / 2
  const transform = `translate(${centerX + camera.panX} ${centerY + camera.panY}) scale(${camera.zoom}) translate(${-centerX} ${-centerY})`

  const handlePointerDown = (event: ReactPointerEvent<SVGSVGElement>) => {
    dragState.current = { x: event.clientX, y: event.clientY }
    event.currentTarget.setPointerCapture(event.pointerId)
  }

  const handlePointerMove = (event: ReactPointerEvent<SVGSVGElement>) => {
    if (!dragState.current) return
    const svg = svgRef.current
    if (!svg) return

    const rect = svg.getBoundingClientRect()
    const dx = ((event.clientX - dragState.current.x) / rect.width) * width / camera.zoom
    const dy = ((event.clientY - dragState.current.y) / rect.height) * height / camera.zoom

    dragState.current = { x: event.clientX, y: event.clientY }
    setCamera((current) => ({
      ...current,
      panX: current.panX - dx,
      panY: current.panY - dy,
    }))
  }

  const handlePointerUp = (event: ReactPointerEvent<SVGSVGElement>) => {
    if (!dragState.current) return
    dragState.current = null
    event.currentTarget.releasePointerCapture(event.pointerId)
  }

  return (
    <div className="overflow-hidden rounded-[1.5rem] border border-border bg-[linear-gradient(140deg,#fbfaf6,#edf3f8)]">
      <div className="flex items-center justify-between border-b border-border/70 px-4 py-3 text-xs text-slate-600">
        <div className="flex items-center gap-4">
          <span>{result.linework.length} paths</span>
          <span>{result.contents.length} content items</span>
          <span>{camera.zoom.toFixed(2)}x zoom</span>
        </div>
        <button
          className="rounded-full border border-border bg-white/80 px-3 py-1 font-medium text-slate-700 transition hover:border-slate-400 hover:bg-white"
          onClick={() => setCamera({ panX: 0, panY: 0, zoom: 1 })}
          type="button"
        >
          Reset View
        </button>
      </div>

      <div className="p-4">
        <svg
          className="h-[520px] w-full touch-none cursor-grab active:cursor-grabbing rounded-[1.1rem] bg-[radial-gradient(circle_at_top,#ffffff,#f5f8fb)]"
          onPointerDown={handlePointerDown}
          onPointerMove={handlePointerMove}
          onPointerUp={handlePointerUp}
          onPointerLeave={handlePointerUp}
          ref={svgRef}
          viewBox={`${bounds.minX - pad} ${bounds.minY - pad} ${width + pad * 2} ${height + pad * 2}`}
        >
          <defs>
            <pattern id="studio-grid-minor" width={GRID_MINOR} height={GRID_MINOR} patternUnits="userSpaceOnUse">
              <path d={`M ${GRID_MINOR} 0 L 0 0 0 ${GRID_MINOR}`} fill="none" stroke="rgba(15,23,42,0.035)" strokeWidth="0.35" />
            </pattern>
            <pattern id="studio-grid-major" width={GRID_MAJOR} height={GRID_MAJOR} patternUnits="userSpaceOnUse">
              <rect width={GRID_MAJOR} height={GRID_MAJOR} fill="url(#studio-grid-minor)" />
              <path d={`M ${GRID_MAJOR} 0 L 0 0 0 ${GRID_MAJOR}`} fill="none" stroke="rgba(15,23,42,0.08)" strokeWidth="0.6" />
            </pattern>
            {contentLayouts.map((layout) => (
              <clipPath id={layout.clipId} key={layout.clipId}>
                <path d={pathToSvgD(layout.clipPath)} />
              </clipPath>
            ))}
          </defs>

          <rect fill="url(#studio-grid-major)" height="100%" width="100%" x={bounds.minX - pad} y={bounds.minY - pad} />

          <g transform={transform}>
            {panelRects.map((panel) => (
              <path
                d={pathToSvgD(panel.path)}
                fill="rgba(255,255,255,0.92)"
                key={`panel-fill-${panel.panelId}`}
                stroke="rgba(217,119,6,0.08)"
                strokeWidth="0.8"
                vectorEffect="non-scaling-stroke"
              />
            ))}

            {contentLayouts.map((layout) => {
              const rotate = `rotate(${((layout.baseAngleRad + layout.content.transform.rotation_rad) * 180) / Math.PI} ${layout.x + layout.w / 2} ${layout.y + layout.h / 2})`
              const panelHeight = layout.anchorBounds.maxY - layout.anchorBounds.minY
              const clipPath = `url(#${layout.clipId})`

              return (
                <BitmapContent2D
                  clipPath={clipPath}
                  content={layout.content}
                  height={layout.h}
                  key={layout.content.id}
                  panelHeight={panelHeight}
                  transform={rotate}
                  width={layout.w}
                  x={layout.x}
                  y={layout.y}
                />
              )
            })}

            {result.linework.map((linework, index) => (
              <path
                d={pathToSvgD(linework.path)}
                fill="none"
                key={`${linework.role}-${index}`}
                stroke={linework.role === 'cut' ? '#c96c10' : linework.role === 'score' ? '#2563eb' : '#64748b'}
                strokeDasharray={linework.stroke_style === 'dashed' ? '8 7' : linework.stroke_style === 'dotted' ? '1.4 5' : undefined}
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={linework.role === 'cut' ? 1.85 : 1.25}
                vectorEffect="non-scaling-stroke"
              />
            ))}
          </g>
        </svg>
      </div>
    </div>
  )
}

function EmptyState({ label }: { label: string }) {
  return (
    <div className="flex h-[520px] items-center justify-center rounded-[1.5rem] border border-dashed border-border bg-white/40 px-6 text-center text-sm text-muted-foreground">
      {label}
    </div>
  )
}

function BitmapContent2D({
  content,
  clipPath,
  x,
  y,
  width,
  height,
  panelHeight,
  transform,
}: {
  content: OutputContentPlacement
  clipPath: string
  x: number
  y: number
  width: number
  height: number
  panelHeight: number
  transform: string
}) {
  const [asset, setAsset] = useState<{ href: string | null; status: 'ready' | 'empty' | 'error' }>({
    href: null,
    status: 'error',
  })
  const request = useMemo(
    () => buildPlacementBitmapRequest(content, width, height, panelHeight),
    [content, height, panelHeight, width],
  )

  useEffect(() => {
    let cancelled = false
    loadContentPreviewDataUrl(request).then(({ dataUrl, status }) => {
      if (!cancelled) setAsset({ href: dataUrl, status })
    })

    return () => {
      cancelled = true
    }
  }, [request])

  return asset.href ? (
    <image
      clipPath={clipPath}
      height={height}
      href={asset.href}
      preserveAspectRatio="none"
      transform={transform}
      width={width}
      x={x}
      y={y}
    />
  ) : (
    <rect
      clipPath={clipPath}
      fill={asset.status === 'error' ? 'rgba(252,165,165,0.22)' : 'rgba(148,163,184,0.2)'}
      height={height}
      stroke={asset.status === 'error' ? 'rgba(185,28,28,0.35)' : 'rgba(71,85,105,0.3)'}
      strokeDasharray="3 3"
      transform={transform}
      width={width}
      x={x}
      y={y}
    />
  )
}
