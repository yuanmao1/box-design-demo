import type {
  GeneratedPackage,
  NumericParamValue,
  OutputContentPlacement,
  TemplatesResponse,
} from '@/types/api'

interface WasmExports {
  memory: WebAssembly.Memory
  allocate: (len: number) => number
  deallocate: (ptr: number, len: number) => void
  list_templates: () => number
  generate_package: (ptr: number, len: number) => number
  get_result_ptr: () => number
  get_result_len: () => number
  free_result: () => void
  get_error_ptr: () => number
  get_error_len: () => number
  free_error: () => void
}

let wasm: WasmExports | null = null

async function ensureWasm() {
  if (wasm) return wasm

  const response = await fetch('/geo-core.wasm')
  const bytes = await response.arrayBuffer()
  const { instance } = await WebAssembly.instantiate(bytes, { env: {} })
  wasm = instance.exports as unknown as WasmExports
  return wasm
}

function readResult(exports: WasmExports) {
  const ptr = exports.get_result_ptr()
  const len = exports.get_result_len()
  const bytes = new Uint8Array(exports.memory.buffer, ptr, len)
  const text = new TextDecoder().decode(bytes)
  exports.free_result()
  return text
}

function readError(exports: WasmExports) {
  const ptr = exports.get_error_ptr()
  const len = exports.get_error_len()
  if (ptr === 0 || len === 0) return 'UnknownWasmError'

  const bytes = new Uint8Array(exports.memory.buffer, ptr, len)
  const text = new TextDecoder().decode(bytes)
  exports.free_error()
  return text
}

async function invokeJson<T>(fn: (exports: WasmExports, ptr: number, len: number) => number, payload?: unknown) {
  const exports = await ensureWasm()

  let ptr = 0
  let len = 0
  if (payload !== undefined) {
    const bytes = new TextEncoder().encode(JSON.stringify(payload))
    len = bytes.length
    ptr = exports.allocate(len)
    if (ptr === 0) {
      throw new Error('WasmAllocateFailed')
    }

    new Uint8Array(exports.memory.buffer).set(bytes, ptr)
  }

  const code = fn(exports, ptr, len)
  if (len > 0) {
    exports.deallocate(ptr, len)
  }

  if (code !== 0) {
    throw new Error(readError(exports))
  }

  return JSON.parse(readResult(exports)) as T
}

export async function listTemplates() {
  return invokeJson<TemplatesResponse>((exports) => exports.list_templates())
}

export async function generatePackage(key: string, numericParams: NumericParamValue[], contents: OutputContentPlacement[]) {
  return invokeJson<GeneratedPackage>((exports, ptr, len) => exports.generate_package(ptr, len), {
    key,
    numeric_params: numericParams,
    contents: contents.map((content) => ({
      id: content.id,
      panel_id: content.panel_id,
      type: content.content.type,
      x: content.transform.position.x,
      y: content.transform.position.y,
      width: content.transform.size.x,
      height: content.transform.size.y,
      rotation: content.transform.rotation_rad,
      text: content.content.type === 'text' ? content.content.text : '',
      image_url: content.content.type === 'image' ? content.content.image_url : '',
      focal_x: content.content.type === 'image' ? content.content.focal_point.x : 50,
      focal_y: content.content.type === 'image' ? content.content.focal_point.y : 50,
      color: content.content.type === 'text' ? content.content.color : '#000000',
      font_size: content.content.type === 'text' ? content.content.font_size : 18,
    })),
  })
}
