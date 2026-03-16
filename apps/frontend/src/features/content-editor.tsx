import { ImagePlus, Type } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { Slider } from '@/components/ui/slider'
import type { OutputContentPlacement } from '@/types/api'

interface PanelOption {
  value: number
  label: string
}

interface ContentEditorProps {
  contents: OutputContentPlacement[]
  panels: PanelOption[]
  selectedContentId: number | null
  onSelect: (id: number) => void
  onAddText: () => void
  onAddImage: () => void
  onRemove: (id: number) => void
  onUpdate: (id: number, patch: Partial<OutputContentPlacement>) => void
}

export function ContentEditor({
  contents,
  panels,
  selectedContentId,
  onSelect,
  onAddText,
  onAddImage,
  onRemove,
  onUpdate,
}: ContentEditorProps) {
  const selected = contents.find((content) => content.id === selectedContentId) ?? contents[0] ?? null
  const selectedText = selected?.content.type === 'text' ? selected.content : null
  const selectedImage = selected?.content.type === 'image' ? selected.content : null

  return (
    <Card className="overflow-hidden">
      <CardHeader>
        <CardTitle>Surface Content</CardTitle>
        <CardDescription>直接编辑 `geo-core` 的内容契约，变更会经 wasm 校验后返回到 2D/3D 预览。</CardDescription>
      </CardHeader>
      <CardContent className="space-y-5">
        <div className="flex gap-3">
          <Button className="flex-1" onClick={onAddText} variant="outline">
            <Type className="h-4 w-4" />
            Add Text
          </Button>
          <Button className="flex-1" onClick={onAddImage} variant="outline">
            <ImagePlus className="h-4 w-4" />
            Add Image
          </Button>
        </div>

        <div className="space-y-2">
          {contents.length === 0 ? (
            <div className="rounded-2xl border border-dashed border-border bg-muted/40 px-4 py-5 text-sm text-muted-foreground">
              No content items yet.
            </div>
          ) : (
            contents.map((content) => {
              const label =
                content.content.type === 'text'
                  ? content.content.text || 'Text item'
                  : content.content.image_url || 'Image item'

              return (
                <div
                  className="flex w-full items-center justify-between rounded-2xl border border-border bg-white/80 px-4 py-3 transition hover:border-primary/40 hover:bg-primary/5"
                  key={content.id}
                >
                  <div>
                    <p className="text-sm font-medium text-slate-900">{label}</p>
                    <p className="text-xs text-muted-foreground">Panel {content.panel_id}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="rounded-full bg-muted px-2 py-1 text-[11px] uppercase tracking-[0.2em] text-muted-foreground">
                      {content.content.type}
                    </span>
                    <Button onClick={() => onSelect(content.id)} size="sm" type="button" variant="outline">
                      Edit
                    </Button>
                    <Button onClick={() => onRemove(content.id)} size="sm" type="button" variant="ghost">
                      Remove
                    </Button>
                  </div>
                </div>
              )
            })
          )}
        </div>

        {selected ? (
          <>
            <Separator />
            <div className="grid gap-4">
              <div className="space-y-2">
                <Label>Panel</Label>
                <Select onValueChange={(value) => onUpdate(selected.id, { panel_id: Number(value) })} value={String(selected.panel_id)}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {panels.map((panel) => (
                      <SelectItem key={panel.value} value={String(panel.value)}>
                        {panel.label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              {selectedText ? (
                <>
                  <LabeledInput
                    label="Text"
                    value={selectedText.text}
                    onChange={(value) =>
                      onUpdate(selected.id, {
                        content: {
                          type: 'text',
                          text: value,
                          color: selectedText.color,
                          font_size: selectedText.font_size,
                        },
                      })
                    }
                  />
                  <LabeledInput
                    label="Color"
                    type="color"
                    value={selectedText.color}
                    onChange={(value) =>
                      onUpdate(selected.id, {
                        content: {
                          type: 'text',
                          text: selectedText.text,
                          color: value,
                          font_size: selectedText.font_size,
                        },
                      })
                    }
                  />
                  <LabeledInput
                    label="Font Size"
                    type="number"
                    value={String(selectedText.font_size)}
                    onChange={(value) =>
                      onUpdate(selected.id, {
                        content: {
                          type: 'text',
                          text: selectedText.text,
                          color: selectedText.color,
                          font_size: Number(value),
                        },
                      })
                    }
                  />
                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <Label>Font Size Preview Scale</Label>
                      <span className="text-xs text-muted-foreground">{selectedText.font_size.toFixed(0)}%</span>
                    </div>
                    <Slider
                      max={100}
                      min={4}
                      onValueChange={([value]) =>
                        onUpdate(selected.id, {
                          content: {
                            type: 'text',
                            text: selectedText.text,
                            color: selectedText.color,
                            font_size: value,
                          },
                        })
                      }
                      step={1}
                      value={[selectedText.font_size]}
                    />
                  </div>
                </>
              ) : selectedImage ? (
                <>
                  <LabeledInput
                    label="Image URL"
                    value={selectedImage.image_url}
                    onChange={(value) =>
                      onUpdate(selected.id, {
                        content: {
                          type: 'image',
                          image_url: value,
                          focal_point: selectedImage.focal_point,
                        },
                      })
                    }
                  />
                  <div className="grid grid-cols-2 gap-3">
                    <LabeledInput
                      label="Focus X %"
                      type="number"
                      value={String(selectedImage.focal_point.x)}
                      onChange={(value) =>
                        onUpdate(selected.id, {
                          content: {
                            type: 'image',
                            image_url: selectedImage.image_url,
                            focal_point: { ...selectedImage.focal_point, x: Number(value) },
                          },
                        })
                      }
                    />
                    <LabeledInput
                      label="Focus Y %"
                      type="number"
                      value={String(selectedImage.focal_point.y)}
                      onChange={(value) =>
                        onUpdate(selected.id, {
                          content: {
                            type: 'image',
                            image_url: selectedImage.image_url,
                            focal_point: { ...selectedImage.focal_point, y: Number(value) },
                          },
                        })
                      }
                    />
                  </div>
                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <Label>Focus X</Label>
                      <span className="text-xs text-muted-foreground">{selectedImage.focal_point.x.toFixed(0)}%</span>
                    </div>
                    <Slider
                      max={100}
                      min={0}
                      onValueChange={([value]) =>
                        onUpdate(selected.id, {
                          content: {
                            type: 'image',
                            image_url: selectedImage.image_url,
                            focal_point: { ...selectedImage.focal_point, x: value },
                          },
                        })
                      }
                      step={1}
                      value={[selectedImage.focal_point.x]}
                    />
                  </div>
                  <div className="space-y-2">
                    <div className="flex items-center justify-between">
                      <Label>Focus Y</Label>
                      <span className="text-xs text-muted-foreground">{selectedImage.focal_point.y.toFixed(0)}%</span>
                    </div>
                    <Slider
                      max={100}
                      min={0}
                      onValueChange={([value]) =>
                        onUpdate(selected.id, {
                          content: {
                            type: 'image',
                            image_url: selectedImage.image_url,
                            focal_point: { ...selectedImage.focal_point, y: value },
                          },
                        })
                      }
                      step={1}
                      value={[selectedImage.focal_point.y]}
                    />
                  </div>
                </>
              ) : null}

              <div className="grid grid-cols-2 gap-3">
                <LabeledInput
                  label="X %"
                  type="number"
                  value={String(selected.transform.position.x)}
                  onChange={(value) =>
                    onUpdate(selected.id, {
                      transform: {
                        ...selected.transform,
                        position: { ...selected.transform.position, x: Number(value) },
                      },
                    })
                  }
                />
                <LabeledInput
                  label="Y %"
                  type="number"
                  value={String(selected.transform.position.y)}
                  onChange={(value) =>
                    onUpdate(selected.id, {
                      transform: {
                        ...selected.transform,
                        position: { ...selected.transform.position, y: Number(value) },
                      },
                    })
                  }
                />
                <LabeledInput
                  label="W %"
                  type="number"
                  value={String(selected.transform.size.x)}
                  onChange={(value) =>
                    onUpdate(selected.id, {
                      transform: {
                        ...selected.transform,
                        size: { ...selected.transform.size, x: Number(value) },
                      },
                    })
                  }
                />
                <LabeledInput
                  label="H %"
                  type="number"
                  value={String(selected.transform.size.y)}
                  onChange={(value) =>
                    onUpdate(selected.id, {
                      transform: {
                        ...selected.transform,
                        size: { ...selected.transform.size, y: Number(value) },
                      },
                    })
                  }
                />
                <LabeledInput
                  label="Rotation"
                  type="number"
                  value={String(selected.transform.rotation_rad)}
                  onChange={(value) =>
                    onUpdate(selected.id, {
                      transform: {
                        ...selected.transform,
                        rotation_rad: Number(value),
                      },
                    })
                  }
                />
                <div className="col-span-2 space-y-2">
                  <div className="flex items-center justify-between">
                    <Label>Rotation</Label>
                    <span className="text-xs text-muted-foreground">{selected.transform.rotation_rad.toFixed(2)} rad</span>
                  </div>
                  <Slider
                    max={Math.PI}
                    min={-Math.PI}
                    onValueChange={([value]) =>
                      onUpdate(selected.id, {
                        transform: {
                          ...selected.transform,
                          rotation_rad: value,
                        },
                      })
                    }
                    step={0.01}
                    value={[selected.transform.rotation_rad]}
                  />
                </div>
              </div>
            </div>
          </>
        ) : null}
      </CardContent>
    </Card>
  )
}

function LabeledInput({
  label,
  value,
  onChange,
  type = 'text',
}: {
  label: string
  value: string
  onChange: (value: string) => void
  type?: string
}) {
  return (
    <div className="space-y-2">
      <Label>{label}</Label>
      <Input onChange={(event) => onChange(event.target.value)} type={type} value={value} />
    </div>
  )
}
