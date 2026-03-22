// WASM integration tests for Flat Bottom Pouch geometry kernel
import { readFileSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'

const __dirname = dirname(fileURLToPath(import.meta.url))
const wasmPath = join(__dirname, 'zig-out/bin/geo-core.wasm')
const wasmBytes = readFileSync(wasmPath)
const { instance } = await WebAssembly.instantiate(wasmBytes, { env: {} })
const ex = instance.exports

let passed = 0
let failed = 0
function check(name, cond) {
  if (cond) { passed++; console.log(`  PASS: ${name}`) }
  else { failed++; console.log(`  FAIL: ${name}`); }
}
function approx(a, b, eps = 0.01) { return Math.abs(a - b) < eps }

function callGenerate(params) {
  const enc = new TextEncoder()
  const dec = new TextDecoder()
  const input = enc.encode(JSON.stringify(params))
  const ptr = ex.allocate(input.length)
  new Uint8Array(ex.memory.buffer).set(input, ptr)
  const rc = ex.generate_package(ptr, input.length)
  ex.deallocate(ptr, input.length)
  if (rc !== 0) throw new Error(`generate_package returned ${rc}`)
  const rp = ex.get_result_ptr()
  const rl = ex.get_result_len()
  const json = new TextDecoder().decode(new Uint8Array(ex.memory.buffer).slice(rp, rp + rl))
  ex.free_result()
  return JSON.parse(json)
}

// ── Test 1: exports ─────────────────────────────────────────
console.log('=== Test 1: Verify exports ===')
for (const name of ['memory','allocate','deallocate','generate_package','get_result_ptr','get_result_len','free_result']) {
  check(`export "${name}"`, name in ex)
}

// ── Test 2: default params ──────────────────────────────────
console.log('\n=== Test 2: Default params (W=89, H=239, G=71, T=30) ===')
const m = callGenerate({ width:89, height:239, gusset_depth:71, top_seal_height:30, bleed_margin:3, safe_margin:5 })

check('template = flat_bottom_pouch', m.template === 'flat_bottom_pouch')
check(`total_width = 249 (G+2W)`, m.total_width === 71 + 2*89)
check(`total_height = 304.5 (T+H+G/2)`, m.total_height === 30 + 239 + 71/2)

// ── Test 3: panels ──────────────────────────────────────────
console.log('\n=== Test 3: 4 panels ===')
check('4 panels', m.panels.length === 4)
const roles = m.panels.map(p => p.role)
check('roles: left_gusset, front, right_gusset, back',
  JSON.stringify(roles) === '["left_gusset","front","right_gusset","back"]')

// Verify panel X boundaries
const G = 71, W = 89, T = 30, H = 239
check('left_gusset x: 0 → G/2', approx(m.panels[0].polygon[0].x, 0) && approx(m.panels[0].polygon[1].x, G/2))
check('front x: G/2 → G/2+W', approx(m.panels[1].polygon[0].x, G/2) && approx(m.panels[1].polygon[1].x, G/2+W))
check('right_gusset x: G/2+W → G+W', approx(m.panels[2].polygon[0].x, G/2+W) && approx(m.panels[2].polygon[1].x, G+W))
check('back x: G+W → G+2W', approx(m.panels[3].polygon[0].x, G+W) && approx(m.panels[3].polygon[1].x, G+2*W))

// safe_polygon is inset by safe_margin from printable
const sp = m.panels[1].safe_polygon
const pp = m.panels[1].printable_polygon
check('safe inset from printable by 5mm', approx(sp[0].x - pp[0].x, 5) && approx(sp[0].y - pp[0].y, 5))

// ── Test 4: fold lines ──────────────────────────────────────
console.log('\n=== Test 4: Fold lines (7 total) ===')
check('7 fold lines', m.fold_lines.length === 7)

const vFolds = m.fold_lines.filter(l => l.start.x === l.end.x)
const hFolds = m.fold_lines.filter(l => l.start.y === l.end.y)
const diagFolds = m.fold_lines.filter(l => l.start.x !== l.end.x && l.start.y !== l.end.y)

check('3 vertical fold lines', vFolds.length === 3)
check('2 horizontal fold lines', hFolds.length === 2)
check('2 diagonal bottom-gusset fold lines', diagFolds.length === 2)

// Verify diagonal: left gusset bottom tuck
const leftDiag = diagFolds.find(l => approx(l.start.x, G/2) && approx(l.start.y, T+H))
check('left diagonal: (G/2, T+H) → (0, T+H+G/2)',
  leftDiag && approx(leftDiag.end.x, 0) && approx(leftDiag.end.y, T+H+G/2))

// Verify diagonal: right gusset bottom tuck
const rightDiag = diagFolds.find(l => approx(l.start.x, G/2+W) && approx(l.start.y, T+H))
check('right diagonal: (G/2+W, T+H) → (G+W, T+H+G/2)',
  rightDiag && approx(rightDiag.end.x, G+W) && approx(rightDiag.end.y, T+H+G/2))

// ── Test 5: cut lines ───────────────────────────────────────
console.log('\n=== Test 5: Cut lines ===')
check('4 cut lines (outer rectangle)', m.cut_lines.length === 4)

// ── Test 6: 3D mesh structure ───────────────────────────────
console.log('\n=== Test 6: 3D Mesh ===')
check('34 vertices', m.mesh.vertices.length === 34)
check('48 indices', m.mesh.indices.length === 48)
check('9 face groups', m.mesh.face_groups.length === 9)

// Verify face group names
const fgNames = m.mesh.face_groups.map(fg => fg.name)
check('face groups: front, back, left_gusset, right_gusset, bottom, front_seal, back_seal, left_seal, right_seal',
  JSON.stringify(fgNames) === '["front","back","left_gusset","right_gusset","bottom","front_seal","back_seal","left_seal","right_seal"]')

// ── Test 7: 3D body geometry ────────────────────────────────
console.log('\n=== Test 7: 3D body geometry ===')
const verts = m.mesh.vertices

// Front face at z = G/2 = 35.5
check('front body z = G/2', verts.slice(0,4).every(v => approx(v.position.z, G/2)))
check('front body normal = (0,0,1)', verts.slice(0,4).every(v =>
  approx(v.normal.x,0) && approx(v.normal.y,0) && approx(v.normal.z,1)))

// Body Y range: 0 to H
check('body bottom y = 0', approx(verts[0].position.y, 0))
check('body top y = H', approx(verts[2].position.y, H))

// Body X range: -W/2 to +W/2
check('body x range: -W/2 to W/2', approx(verts[0].position.x, -W/2) && approx(verts[1].position.x, W/2))

// ── Test 8: 3D seal taper ───────────────────────────────────
console.log('\n=== Test 8: 3D seal taper ===')

// Front seal vertices (20-23): bottom at z=G/2, top at z=0
check('front seal bottom z = G/2', approx(verts[20].position.z, G/2) && approx(verts[21].position.z, G/2))
check('front seal top z = 0 (sealed)', approx(verts[22].position.z, 0) && approx(verts[23].position.z, 0))
check('front seal top y = H+T', approx(verts[22].position.y, H+T))

// Back seal similarly
check('back seal bottom z = -G/2', approx(verts[24].position.z, -G/2))
check('back seal top z = 0', approx(verts[26].position.z, 0) && approx(verts[27].position.z, 0))

// Side seal triangles meet at z=0
check('left seal apex at z=0', approx(verts[30].position.z, 0))
check('right seal apex at z=0', approx(verts[33].position.z, 0))

// Seal normals have Y component (tilted)
check('front seal normal tilts up+forward', verts[20].normal.y > 0 && verts[20].normal.z > 0)
check('back seal normal tilts up+backward', verts[24].normal.y > 0 && verts[24].normal.z < 0)

// ── Test 9: UV mapping ──────────────────────────────────────
console.log('\n=== Test 9: UV mapping ===')
const tw = G + 2*W
const th = T + H + G/2

// Front body: UV should map to front panel in 2D dieline
check('front body UV u range: x1/tw to x2/tw',
  approx(verts[0].uv.x, (G/2)/tw) && approx(verts[1].uv.x, (G/2+W)/tw))
check('front body UV v range: y1/th to y2/th',
  approx(verts[2].uv.y, T/th) && approx(verts[0].uv.y, (T+H)/th))

// Seal UV: top edge maps to y0=0
check('front seal top UV v = 0', approx(verts[22].uv.y, 0))

// ── Test 10: custom params ──────────────────────────────────
console.log('\n=== Test 10: Custom params ===')
const m2 = callGenerate({ width:100, height:200, gusset_depth:50, top_seal_height:20, bleed_margin:2, safe_margin:4 })
check('custom total_width = 250', m2.total_width === 50 + 200)
check('custom total_height = 245', m2.total_height === 20 + 200 + 25)
check('custom 7 fold lines', m2.fold_lines.length === 7)
check('custom 34 verts', m2.mesh.vertices.length === 34)
check('custom 9 face groups', m2.mesh.face_groups.length === 9)

// ══════════════════════════════════════════════════════════════
//  MAILER BOX TESTS
// ══════════════════════════════════════════════════════════════

// ── Test 11: mailer_box default params ──────────────────────
console.log('\n=== Test 11: Mailer Box default params ===')
const mb = callGenerate({
  template: 'mailer_box',
  width: 200, height: 150, depth: 80,
  lid_height: 150, tuck_height: 20, dust_flap_height: 30,
  bleed_margin: 3, safe_margin: 5
})

check('mb template = mailer_box', mb.template === 'mailer_box')
const mbW = 200, mbH = 150, mbD = 80
check('mb total_width = 2D+2W = 560', mb.total_width === 2*mbD + 2*mbW)
check('mb total_height = dust+H+D/2+lid+tuck = 390', mb.total_height === 30 + 150 + 40 + 150 + 20)

// ── Test 12: mailer_box panels ──────────────────────────────
console.log('\n=== Test 12: Mailer Box panels (18 total) ===')
check('mb 18 panels', mb.panels.length === 18)

const mbRoles = mb.panels.map(p => p.role)
check('mb roles correct', JSON.stringify(mbRoles) === JSON.stringify([
  'mb_dust_fl','mb_dust_fr','mb_dust_bl','mb_dust_br',
  'mb_left','mb_front','mb_right','mb_back',
  'mb_bot_fl','mb_bot_fr','mb_bot_bl','mb_bot_br',
  'mb_reinf_l','mb_lid','mb_reinf_r',
  'mb_tuck_l','mb_tuck','mb_tuck_r'
]))

// Verify designable flags
const mbDesignable = mb.panels.filter(p => p.designable)
check('mb 5 designable panels', mbDesignable.length === 5)
check('mb designable: left,front,right,back,lid',
  JSON.stringify(mbDesignable.map(p => p.role)) ===
  JSON.stringify(['mb_left','mb_front','mb_right','mb_back','mb_lid']))

const mbStructural = mb.panels.filter(p => !p.designable)
check('mb 13 structural panels', mbStructural.length === 13)

// ── Test 13: mailer_box panel coordinates ───────────────────
console.log('\n=== Test 13: Mailer Box panel coordinates ===')
// X boundaries: x0=0, x1=D=80, x2=D+W=280, x3=2D+W=360, x4=2D+2W=560
const mbFront = mb.panels.find(p => p.role === 'mb_front')
check('mb_front x: D → D+W', approx(mbFront.polygon[0].x, 80) && approx(mbFront.polygon[1].x, 280))
// Y boundaries for body: y1=30, y2=180
check('mb_front y: dust_h → dust_h+H', approx(mbFront.polygon[0].y, 30) && approx(mbFront.polygon[2].y, 180))

const mbLid = mb.panels.find(p => p.role === 'mb_lid')
// y3 = 30+150+40 = 220, y4 = 220+150 = 370
check('mb_lid y: y3→y4', approx(mbLid.polygon[0].y, 220) && approx(mbLid.polygon[2].y, 370))
check('mb_lid x: D→D+W', approx(mbLid.polygon[0].x, 80) && approx(mbLid.polygon[1].x, 280))

const mbTuck = mb.panels.find(p => p.role === 'mb_tuck')
check('mb_tuck y: y4→y5', approx(mbTuck.polygon[0].y, 370) && approx(mbTuck.polygon[2].y, 390))

// ── Test 13b: reinforce & tuck tab panels ───────────────────
console.log('\n=== Test 13b: Reinforce & tuck tab panels ===')
const mbReinfL = mb.panels.find(p => p.role === 'mb_reinf_l')
check('mb_reinf_l x: 0→D', approx(mbReinfL.polygon[0].x, 0) && approx(mbReinfL.polygon[1].x, 80))
check('mb_reinf_l y: y3→y4', approx(mbReinfL.polygon[0].y, 220) && approx(mbReinfL.polygon[2].y, 370))

const mbReinfR = mb.panels.find(p => p.role === 'mb_reinf_r')
check('mb_reinf_r x: D+W→2D+W', approx(mbReinfR.polygon[0].x, 280) && approx(mbReinfR.polygon[1].x, 360))

const mbTuckL = mb.panels.find(p => p.role === 'mb_tuck_l')
check('mb_tuck_l y: y4→y5', approx(mbTuckL.polygon[0].y, 370) && approx(mbTuckL.polygon[2].y, 390))

const mbTuckR = mb.panels.find(p => p.role === 'mb_tuck_r')
check('mb_tuck_r x: D+W→2D+W', approx(mbTuckR.polygon[0].x, 280) && approx(mbTuckR.polygon[1].x, 360))

// ── Test 14: mailer_box fold lines ──────────────────────────
console.log('\n=== Test 14: Mailer Box fold lines ===')
check('mb 7 fold lines', mb.fold_lines.length === 7)

// Verify fold line structure
const mbFolds = mb.fold_lines
// Vertical: x1 full height, x2 full height, x3 partial
check('mb fold x1 full height: y0→y5', approx(mbFolds[0].start.x, 80) && approx(mbFolds[0].end.y, 390))
check('mb fold x2 full height: y0→y5', approx(mbFolds[1].start.x, 280) && approx(mbFolds[1].end.y, 390))
check('mb fold x3 partial: y0→y3', approx(mbFolds[2].start.x, 360) && approx(mbFolds[2].end.y, 220))
// Horizontal: y1 full width, y2 full width, y3 3-col, y4 3-col
check('mb fold y1 full: x0→x4', approx(mbFolds[3].end.x, 560))
check('mb fold y2 full: x0→x4', approx(mbFolds[4].end.x, 560))
check('mb fold y3 3-col: x0→x3', approx(mbFolds[5].end.x, 360))
check('mb fold y4 3-col: x0→x3', approx(mbFolds[6].end.x, 360))

// ── Test 15: mailer_box cut lines ───────────────────────────
console.log('\n=== Test 15: Mailer Box cut lines ===')
check('mb 6 cut lines (L-shaped perimeter)', mb.cut_lines.length === 6)

// Verify L-shape: back column stops at y3, left/front/right extend to y5
const mbCuts = mb.cut_lines
check('mb cut top: x0,y0 → x4,y0', approx(mbCuts[0].start.x, 0) && approx(mbCuts[0].end.x, 560))
check('mb cut right: x4,y0 → x4,y3', approx(mbCuts[1].start.y, 0) && approx(mbCuts[1].end.y, 220))
check('mb cut step: x4,y3 → x3,y3', approx(mbCuts[2].start.x, 560) && approx(mbCuts[2].end.x, 360))
check('mb cut right-col: x3,y3 → x3,y5', approx(mbCuts[3].start.y, 220) && approx(mbCuts[3].end.y, 390))
check('mb cut bottom: x3,y5 → x0,y5', approx(mbCuts[4].start.x, 360) && approx(mbCuts[4].end.x, 0))
check('mb cut left: x0,y5 → x0,y0', approx(mbCuts[5].start.y, 390) && approx(mbCuts[5].end.y, 0))

// ── Test 16: mailer_box 3D mesh ─────────────────────────────
console.log('\n=== Test 16: Mailer Box 3D mesh ===')
check('mb 24 vertices', mb.mesh.vertices.length === 24)
check('mb 36 indices', mb.mesh.indices.length === 36)
check('mb 6 face groups', mb.mesh.face_groups.length === 6)

const mbFgNames = mb.mesh.face_groups.map(fg => fg.name)
check('mb face groups: front,back,left,right,top,bottom',
  JSON.stringify(mbFgNames) === JSON.stringify(['front','back','left','right','top','bottom']))

// ── Test 17: mailer_box 3D geometry ─────────────────────────
console.log('\n=== Test 17: Mailer Box 3D geometry ===')
const mbVerts = mb.mesh.vertices

// Front face at z = D/2 = 40
check('mb front z = D/2', mbVerts.slice(0,4).every(v => approx(v.position.z, mbD/2)))
check('mb front normal = (0,0,1)', mbVerts.slice(0,4).every(v =>
  approx(v.normal.x,0) && approx(v.normal.y,0) && approx(v.normal.z,1)))

// Body dimensions
check('mb body x range: -W/2 to W/2', approx(mbVerts[0].position.x, -mbW/2) && approx(mbVerts[1].position.x, mbW/2))
check('mb body y range: 0 to H', approx(mbVerts[0].position.y, 0) && approx(mbVerts[2].position.y, mbH))

// ── Test 18: mailer_box with template field defaults ────────
console.log('\n=== Test 18: Mailer Box backward compat (no template → flat_bottom_pouch) ===')
const mDefault = callGenerate({ width:89, height:239, gusset_depth:71, top_seal_height:30, bleed_margin:3, safe_margin:5 })
check('no template field → flat_bottom_pouch', mDefault.template === 'flat_bottom_pouch')

// ── Summary ─────────────────────────────────────────────────
console.log(`\n${'='.repeat(50)}`)
console.log(`Results: ${passed} passed, ${failed} failed`)
if (failed > 0) process.exit(1)
console.log('All tests passed!')
