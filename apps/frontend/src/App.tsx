import { lazy, Suspense, useDeferredValue, useEffect, useMemo, useRef, useState, startTransition, type ReactNode } from 'react'
import { Box, Boxes, Loader2, Package2, Ruler } from 'lucide-react'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { Slider } from '@/components/ui/slider'
import { ContentEditor } from '@/features/content-editor'
import { DielinePreview } from '@/features/dieline-preview'
import { createContent, describeWasmError, mergeContentPatch } from '@/lib/package-editor'
import { generatePackage, listTemplates } from '@/lib/wasm'
import { cn } from '@/lib/utils'
import type { GeneratedPackage, NumericParamDef, NumericParamValue, OutputContent, OutputContentPlacement, TemplateDescriptor } from '@/types/api'

const Preview3DCanvas = lazy(() => import('@/features/preview-3d-canvas').then((module) => ({ default: module.Preview3DCanvas })))

function numericParamsFromDescriptor(template: TemplateDescriptor) {
  return Object.fromEntries(template.numeric_params.map((param) => [param.key, param.default_value]))
}

function paramStep(param: NumericParamDef) {
  return param.key.includes('angle') ? 0.01 : 1
}

function formatParamValue(param: NumericParamDef, value: number) {
  return param.key.includes('angle') ? `${value.toFixed(2)} rad` : `${value.toFixed(0)} mm`
}

function App() {
  const [templates, setTemplates] = useState<TemplateDescriptor[]>([])
  const [selectedKey, setSelectedKey] = useState('')
  const [params, setParams] = useState<Record<string, number>>({})
  const [generated, setGenerated] = useState<GeneratedPackage | null>(null)
  const [contents, setContents] = useState<OutputContentPlacement[]>([])
  const [selectedContentId, setSelectedContentId] = useState<number | null>(null)
  const [loadingTemplates, setLoadingTemplates] = useState(true)
  const [loadingPackage, setLoadingPackage] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const hydratedRef = useRef(false)
  const latestGenerateId = useRef(0)

  const selectedTemplate = templates.find((template) => template.key === selectedKey) ?? null
  const deferredKey = useDeferredValue(selectedKey)
  const deferredParams = useDeferredValue(params)

  useEffect(() => {
    let cancelled = false

    void (async () => {
      try {
        const response = await listTemplates()
        if (cancelled) return

        startTransition(() => {
          setTemplates(response.templates)
          const firstTemplate = response.templates[0]
          if (firstTemplate) {
            setSelectedKey(firstTemplate.key)
            setParams(numericParamsFromDescriptor(firstTemplate))
          }
          setLoadingTemplates(false)
        })
      } catch (nextError) {
        if (cancelled) return
        setError(nextError instanceof Error ? nextError.message : String(nextError))
        setLoadingTemplates(false)
      }
    })()

    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (!deferredKey || !selectedTemplate) return
    if (!hydratedRef.current) {
      hydratedRef.current = true
    }

    const requestId = ++latestGenerateId.current
    setLoadingPackage(true)

    void (async () => {
      try {
        const payload: NumericParamValue[] = Object.entries(deferredParams).map(([key, value]) => ({ key, value }))
        const nextGenerated = await generatePackage(deferredKey, payload, contents)
        if (requestId !== latestGenerateId.current) return

        startTransition(() => {
          setGenerated(nextGenerated)
          setError(null)
          setLoadingPackage(false)
        })
      } catch (nextError) {
        if (requestId !== latestGenerateId.current) return
        setError(nextError instanceof Error ? nextError.message : String(nextError))
        setLoadingPackage(false)
      }
    })()
  }, [contents, deferredKey, deferredParams, selectedTemplate])

  const changeTemplate = (key: string) => {
    const nextTemplate = templates.find((template) => template.key === key)
    if (!nextTemplate) return
    setSelectedKey(key)
    setParams(numericParamsFromDescriptor(nextTemplate))
    setContents([])
    setSelectedContentId(null)
  }

  const updateParam = (key: string, value: number) => {
    setParams((current) => ({ ...current, [key]: value }))
  }

  const panelOptions = useMemo(() => {
    const ids = [...new Set((generated?.preview_3d.nodes ?? []).flatMap((node) => (node.panel_id == null ? [] : [node.panel_id])))]
    return ids.map((id) => ({ value: id, label: `Panel ${id}` }))
  }, [generated])
  const selectedContent = useMemo(
    () => contents.find((content) => content.id === selectedContentId) ?? null,
    [contents, selectedContentId],
  )
  const errorDescription = describeWasmError(error)

  const addContent = (type: OutputContent['type']) => {
    const panelId = panelOptions[0]?.value ?? 0
    const next = createContent(type, panelId)
    setContents((current) => [...current, next])
    setSelectedContentId(next.id)
  }

  const updateContent = (id: number, patch: Partial<OutputContentPlacement>) => {
    setContents((current) => current.map((content) => (content.id === id ? mergeContentPatch(content, patch) : content)))
  }

  const removeContent = (id: number) => {
    setContents((current) => current.filter((content) => content.id !== id))
    setSelectedContentId((current) => (current === id ? null : current))
  }

  return (
    <div className="min-h-screen px-4 py-6 text-foreground md:px-6 lg:px-8">
      <div className="mx-auto flex w-full max-w-[1600px] flex-col gap-6">
        {error ? (
          <div className="rounded-[1.5rem] border border-red-200 bg-red-50 px-4 py-4 text-sm text-red-700">
            <p className="font-medium">{errorDescription}</p>
            <p className="mt-1 text-red-600/90">Raw error: <code>{error}</code></p>
            {selectedContent ? (
              <pre className="mt-3 overflow-x-auto rounded-xl border border-red-200/80 bg-white/70 p-3 text-xs text-slate-700">
                {JSON.stringify(selectedContent, null, 2)}
              </pre>
            ) : null}
          </div>
        ) : null}

        <div className="grid gap-6 xl:grid-cols-[340px_minmax(0,1fr)]">
          <div className="space-y-6">
            <Card className="overflow-hidden">
              <CardHeader>
                <CardTitle>Template Control</CardTitle>
                <CardDescription>模板清单和参数来自 `geo-core` 的导出函数。</CardDescription>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="space-y-2">
                  <Label htmlFor="template-select">Template</Label>
                  <Select disabled={loadingTemplates || templates.length === 0} onValueChange={changeTemplate} value={selectedKey}>
                    <SelectTrigger id="template-select">
                      <SelectValue placeholder="Select a template" />
                    </SelectTrigger>
                    <SelectContent>
                      {templates.map((template) => (
                        <SelectItem key={template.key} value={template.key}>
                          {template.label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>

                <Separator />

                <div className="space-y-5">
                  {selectedTemplate?.numeric_params.map((param) => {
                    const value = params[param.key] ?? param.default_value
                    return (
                      <div key={param.key} className="space-y-3">
                        <div className="flex items-center justify-between gap-3">
                          <div>
                            <Label>{param.label}</Label>
                            <p className="text-xs text-muted-foreground">{param.key}</p>
                          </div>
                          <Badge variant="outline">{formatParamValue(param, value)}</Badge>
                        </div>
                        <Slider
                          max={param.max_value ?? Math.max(param.default_value * 2, value)}
                          min={param.min_value ?? 0}
                          onValueChange={([nextValue]) => updateParam(param.key, nextValue)}
                          step={paramStep(param)}
                          value={[value]}
                        />
                        <Input
                          min={param.min_value ?? undefined}
                          max={param.max_value ?? undefined}
                          onChange={(event) => updateParam(param.key, Number(event.target.value))}
                          step={paramStep(param)}
                          type="number"
                          value={Number.isFinite(value) ? value : ''}
                        />
                      </div>
                    )
                  })}
                </div>

                <Button
                  className="w-full"
                  onClick={() => {
                    if (!selectedTemplate) return
                    setParams(numericParamsFromDescriptor(selectedTemplate))
                  }}
                  variant="secondary"
                >
                  Reset Parameters
                </Button>
              </CardContent>
            </Card>

            <ContentEditor
              contents={contents}
              onAddImage={() => addContent('image')}
              onAddText={() => addContent('text')}
              onRemove={removeContent}
              onSelect={setSelectedContentId}
              onUpdate={updateContent}
              panels={panelOptions}
              selectedContentId={selectedContentId}
            />

            <Card className="overflow-hidden">
              <CardHeader>
                <CardTitle>Debug</CardTitle>
                <CardDescription>当前编辑内容和最近一次 wasm 返回状态。</CardDescription>
              </CardHeader>
              <CardContent className="space-y-3 text-xs">
                <div className="flex items-center justify-between rounded-xl border border-border bg-muted/30 px-3 py-2">
                  <span className="text-muted-foreground">Last Status</span>
                  <span className={cn('font-medium', error ? 'text-red-600' : 'text-emerald-600')}>{error ? 'failed' : 'ok'}</span>
                </div>
                <div className="flex items-center justify-between rounded-xl border border-border bg-muted/30 px-3 py-2">
                  <span className="text-muted-foreground">Content Count</span>
                  <span className="font-medium text-slate-900">{contents.length}</span>
                </div>
                <pre className="max-h-72 overflow-auto rounded-xl border border-border bg-slate-950 p-3 text-[11px] leading-5 text-slate-100">
                  {JSON.stringify(
                    {
                      selected_template: selectedKey,
                      numeric_params: params,
                      selected_content: selectedContent,
                    },
                    null,
                    2,
                  )}
                </pre>
              </CardContent>
            </Card>
          </div>

          <div className="grid gap-6 2xl:grid-cols-[minmax(0,1.08fr)_minmax(0,0.92fr)]">
            <PreviewPanel description="按 `Drawing2DResult` 直接渲染刀线和内容，并支持拖拽查看。" loading={loadingPackage} title="2D Dieline">
              <DielinePreview result={generated?.drawing_2d ?? null} />
            </PreviewPanel>

            <PreviewPanel description="按 `Fold` 图生成的层级节点和局部折叠 transform，3D 部分按需懒加载。" loading={loadingPackage} title="3D Preview">
              <Suspense fallback={<EmptyState label="Loading 3D renderer chunk..." />}>
                <Preview3DCanvas result={generated?.preview_3d ?? null} />
              </Suspense>
            </PreviewPanel>
          </div>
        </div>
      </div>
    </div>
  )
}

function Metric({
  icon: Icon,
  label,
  value,
}: {
  icon: typeof Package2
  label: string
  value: number
}) {
  return (
    <div className="rounded-[1.25rem] border border-white/10 bg-white/5 p-4">
      <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-full bg-white/10">
        <Icon className="h-5 w-5" />
      </div>
      <p className="text-xs uppercase tracking-[0.25em] text-slate-400">{label}</p>
      <p className="mt-2 text-2xl font-semibold">{value}</p>
    </div>
  )
}

function PreviewPanel({
  title,
  description,
  loading,
  children,
}: {
  title: string
  description: string
  loading: boolean
  children: ReactNode
}) {
  return (
    <Card className="overflow-hidden">
      <CardHeader className="flex flex-row items-end justify-between gap-4">
        <div>
          <CardTitle>{title}</CardTitle>
          <CardDescription>{description}</CardDescription>
        </div>
        <Badge className={cn('transition-opacity', loading ? 'opacity-100' : 'opacity-0')} variant="outline">
          <Loader2 className="mr-2 h-3.5 w-3.5 animate-spin" />
          syncing
        </Badge>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  )
}

function EmptyState({ label }: { label: string }) {
  return (
    <div className="flex h-[520px] items-center justify-center rounded-[1.5rem] border border-dashed border-border bg-white/40 px-6 text-center text-sm text-muted-foreground">
      {label}
    </div>
  )
}

export default App
