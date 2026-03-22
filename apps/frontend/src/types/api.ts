export interface NumericParamDef {
  key: string
  label: string
  default_value: number
  min_value: number | null
  max_value: number | null
}

export interface SelectParamOptionDef {
  value: string
  label: string
}

export interface SelectParamDef {
  key: string
  label: string
  default_value: string
  options: SelectParamOptionDef[]
}

export interface TemplateDescriptor {
  key: string
  label: string
  package_kind: string
  numeric_params: NumericParamDef[]
  select_params: SelectParamDef[]
}

export interface TemplatesResponse {
  templates: TemplateDescriptor[]
}

export interface Vec2 {
  x: number
  y: number
}

export interface Vec3 {
  x: number
  y: number
  z: number
}

export interface SurfaceFrame2D {
  origin: Vec2
  u_axis: Vec2
  v_axis: Vec2
}

export type PathSeg =
  | { kind: 'Line'; from: Vec2; to: Vec2 }
  | { kind: 'Arc'; center: Vec2; radius: number; startAngle: number; endAngle: number; clockwise: boolean }
  | { kind: 'Bezier'; p0: Vec2; p1: Vec2; p2: Vec2; p3: Vec2 }

export interface Path2D {
  closed: boolean
  segments: PathSeg[]
}

export interface StyledPath2D {
  role: 'cut' | 'bleed' | 'safe' | 'fold' | 'score' | 'guide'
  stroke_style: 'solid' | 'dashed' | 'dotted'
  path: Path2D
}

export interface Drawing2DPanel {
  panel_id: number
  name: string
  boundary: Path2D
  content_region: Path2D
  surface_frame: SurfaceFrame2D
  accepts_content: boolean
}

export interface Drawing2DResult {
  panels: Drawing2DPanel[]
  linework: StyledPath2D[]
  contents: OutputContentPlacement[]
}

export interface PreviewTransform3D {
  translation: Vec3
  rotation_origin: Vec3
  rotation_axis: Vec3
  rotation_rad: number
  scale: Vec3
}

export interface OutputContentTransform {
  position: Vec2
  size: Vec2
  rotation_rad: number
  space: 'panel_local' | 'panel_uv_percent'
}

export type OutputContent =
  | {
      type: 'text'
      text: string
      font_size: number
      color: string
    }
  | {
      type: 'image'
      image_url: string
      focal_point: Vec2
    }

export interface OutputContentPlacement {
  id: number
  panel_id: number
  transform: OutputContentTransform
  clip_path: Path2D | null
  surface_frame: SurfaceFrame2D | null
  z_index: number
  content: OutputContent
}

export interface Preview3DNode {
  kind: 'panel' | 'shell'
  parent_index: number | null
  panel_id: number | null
  hinge_segment_index: number | null
  boundary: Path2D | null
  surface_frame: SurfaceFrame2D | null
  outside_normal: Vec3 | null
  transform: PreviewTransform3D
}

export interface Preview3DResult {
  nodes: Preview3DNode[]
  contents: OutputContentPlacement[]
}

export interface GeneratedPackage {
  template_key: string
  drawing_2d: Drawing2DResult
  preview_3d: Preview3DResult
}

export interface NumericParamValue {
  key: string
  value: number
}

export interface SelectParamValue {
  key: string
  value: string
}
