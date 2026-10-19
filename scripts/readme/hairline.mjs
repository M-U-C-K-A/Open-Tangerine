/*
 * Hairline figures for the README: isometric line drawings in a single 1px
 * stroke, rounded solids drawn as a silhouette and one crease, plates filled
 * with the page colour, one bright stroke (the tangerine accent), and no
 * words inside the drawing.
 *
 *   node scripts/readme/hairline.mjs   →   docs/readme/hairline-<name>-{light,dark}.svg
 *
 * The visual language follows @lucasmarkes/hairline; the geometry below is
 * written for static files (no pointer, a short ambient loop instead).
 */

import { mkdirSync, writeFileSync } from "fs"
import { dirname, join } from "path"
import { fileURLToPath } from "url"

const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "docs", "readme")
mkdirSync(OUT, { recursive: true })

/* ---- palette: four strokes, the accent as the bright one -------------- */

const THEMES = {
  light: { ground: "#ffffff", hi: "#e04f00", edge: "#a6a69a", mid: "#c4c4b9", lo: "#e1e1d8" },
  dark: { ground: "#0d1117", hi: "#ff8a4c", edge: "#6e7166", mid: "#494c44", lo: "#2f322c" },
}

const EASE = "0.32 0.72 0 1"
const LIN = "0 0 1 1"
const r2 = (n) => Math.round(n * 100) / 100

/* ---- camera: azimuth 45°, k = 0.5 (the 2:1 view) ---------------------- */

function camera(S) {
  const c = Math.cos(Math.PI / 4)
  const s = Math.sin(Math.PI / 4)
  const k = 0.5
  const zf = Math.sqrt(1 - k * k)
  const cam = { ox: 0, oy: 0, S, k, zf }
  cam.P = (x, y, z = 0) => [r2(cam.ox + S * (x * c - y * s)), r2(cam.oy + S * ((x * s + y * c) * k - z * zf))]
  cam.front = (q) => q.nu * s + q.nv * c >= -1e-6
  cam.depth = (x, y) => x * s + y * c
  /** Screen offset of a rise of dz. */
  cam.up = (dz) => r2(S * dz * zf)
  cam.fit = (points, cx, cy) => {
    cam.ox = 0
    cam.oy = 0
    const xs = points.map((p) => cam.P(...p))
    const minX = Math.min(...xs.map((p) => p[0]))
    const maxX = Math.max(...xs.map((p) => p[0]))
    const minY = Math.min(...xs.map((p) => p[1]))
    const maxY = Math.max(...xs.map((p) => p[1]))
    cam.ox = cx - (minX + maxX) / 2
    cam.oy = cy - (minY + maxY) / 2
  }
  return cam
}

/** A camera scaled so `points` fill W × H, less a margin, centred. */
function framed(points, W, H, margin = 34, dy = 0) {
  const unit = camera(1)
  const xs = points.map((p) => unit.P(...p))
  const bw = Math.max(...xs.map((p) => p[0])) - Math.min(...xs.map((p) => p[0]))
  const bh = Math.max(...xs.map((p) => p[1])) - Math.min(...xs.map((p) => p[1]))
  const cam = camera(Math.min((W - margin * 2) / bw, (H - margin * 2) / bh))
  cam.fit(points, W / 2, H / 2 + dy)
  return cam
}

/** Points round a circle, for framing round things. */
const circle = (cx, cy, R, z, n = 24) => Array.from({ length: n }, (_, i) => [cx + R * Math.cos((i / n) * Math.PI * 2), cy + R * Math.sin((i / n) * Math.PI * 2), z])

/** A rounded rectangle as a ring of samples with outward normals. */
function rrect(u0, v0, u1, v1, r, n = 4) {
  r = Math.max(0, Math.min(r, (u1 - u0) / 2, (v1 - v0) / 2))
  const out = []
  for (const [cu, cv, a0] of [
    [u1 - r, v1 - r, 0],
    [u0 + r, v1 - r, 90],
    [u0 + r, v0 + r, 180],
    [u1 - r, v0 + r, 270],
  ]) {
    for (let i = 0; i <= n; i += 1) {
      const a = ((a0 + (90 * i) / n) * Math.PI) / 180
      out.push({ u: cu + r * Math.cos(a), v: cv + r * Math.sin(a), nu: Math.cos(a), nv: Math.sin(a) })
    }
  }
  return out
}

/** A round footprint: a rounded square whose radius is half its side. */
const round = (cx, cy, R, n = 14) => rrect(cx - R, cy - R, cx + R, cy + R, R, n)

/** The ring split into its camera-facing run and the rest, both in ring order. */
function split(cam, ring) {
  const n = ring.length
  let start = 0
  for (let i = 0; i < n; i += 1) {
    if (cam.front(ring[i]) && !cam.front(ring[(i + n - 1) % n])) {
      start = i
      break
    }
  }
  const order = Array.from({ length: n }, (_, i) => ring[(start + i) % n])
  const cut = order.findIndex((q) => !cam.front(q))
  return { front: order.slice(0, cut), back: order.slice(cut) }
}

const pathOf = (pts, close = true) => `M${pts.map((p) => `${p[0]} ${p[1]}`).join("L")}${close ? "Z" : ""}`

/**
 * A rounded solid from z0 to z1: its silhouette (front arc at the base, back
 * arc at the top) and its crease (the inner ring's front arc on top). The
 * point count does not depend on the height, so heights can be animated.
 */
function solid(cam, ring, inner, z0, z1) {
  const { front, back } = split(cam, ring)
  const sil = [
    ...front.map((q) => cam.P(q.u, q.v, z0)),
    cam.P(front[front.length - 1].u, front[front.length - 1].v, z1),
    ...back.map((q) => cam.P(q.u, q.v, z1)),
    cam.P(front[0].u, front[0].v, z1),
  ]
  const crease = inner ? split(cam, inner).front.map((q) => cam.P(q.u, q.v, z1)) : []
  return { sil: pathOf(sil), crease: crease.length > 1 ? pathOf(crease, false) : "" }
}

/** Convex hull, for solids that are not extruded straight up (a laptop lid). */
function hull(points) {
  const p = points.slice().sort((a, b) => a[0] - b[0] || a[1] - b[1])
  const cross = (o, a, b) => (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
  const lower = []
  for (const q of p) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], q) <= 0) lower.pop()
    lower.push(q)
  }
  const upper = []
  for (const q of p.reverse()) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], q) <= 0) upper.pop()
    upper.push(q)
  }
  upper.pop()
  lower.pop()
  return lower.concat(upper)
}

const ringPath = (cam, ring, z) => pathOf(ring.map((q) => cam.P(q.u, q.v, z)))
const line = (cam, a, b) => `M${cam.P(...a).join(" ")}L${cam.P(...b).join(" ")}`
const el = (d, cls = "") => (d ? `<path d="${d}"${cls ? ` class="${cls}"` : ""}/>` : "")
const dot = (cam, x, y, z, cls = "dot", rx = 2.2) => {
  const [px, py] = cam.P(x, y, z)
  return `<ellipse cx="${px}" cy="${py}" rx="${rx}" ry="${r2(rx / 2)}" class="${cls}"/>`
}

/** A plate (a slab with a silhouette and one crease) at z0..z1. */
function plate(cam, x0, y0, x1, y1, r, b, z0, z1, cls = "sil", n = 4) {
  const s = solid(cam, rrect(x0, y0, x1, y1, r, n), rrect(x0 + b, y0 + b, x1 - b, y1 - b, Math.max(0.3, r - b), n), z0, z1)
  return el(s.sil, cls) + el(s.crease, "lo nf")
}

/* ---- svg ---------------------------------------------------------------- */

function document(width, height, title, theme, body) {
  const t = THEMES[theme]
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="${title}">
  <title>${title}</title>
  <style>
    path, ellipse, rect { fill: ${t.ground}; stroke: ${t.mid}; stroke-width: 1; vector-effect: non-scaling-stroke; stroke-linejoin: round; stroke-linecap: round; }
    .sil { stroke: ${t.edge}; }
    .hi { stroke: ${t.hi}; }
    .lo { stroke: ${t.lo}; }
    .nf { fill: none; }
    .dash { fill: none; stroke: ${t.edge}; stroke-dasharray: 1.5 4; }
    .dash.lo { stroke: ${t.lo}; }
    .dot { stroke: none; fill: ${t.hi}; }
    .dot.m { fill: ${t.edge}; }
    .dot.off { fill: ${t.lo}; }
  </style>
  ${body}
</svg>
`
}

/**
 * Keyframes for a figure that steps through `n` poses: a move of `move` ms,
 * then a hold, each step `period` ms. Returns the shared keyTimes and splines,
 * and `values(f)` which samples f(step) at every key (wrapping to the last).
 */
function steps(n, period, move) {
  const dur = n * period
  const times = [0]
  const splines = []
  for (let j = 0; j < n; j += 1) {
    times.push(j * period + move, (j + 1) * period)
    splines.push(EASE, LIN)
  }
  return {
    dur,
    keyTimes: times.map((t) => r2(t / dur)).join(";"),
    keySplines: splines.join(";"),
    values: (f) => [f(n - 1), ...Array.from({ length: n }, (_, j) => [f(j), f(j)]).flat()].join(";"),
  }
}

/* ---- 1. drop: a file hovers over the dial; the format under it rises --- */

function drop(theme) {
  const W = 640
  const H = 440
  const R = 92
  const zTop = 7
  const n = 8
  const ringR = 62
  const z0 = 58
  const cam = framed([...circle(0, 0, R, 0), ...circle(0, 0, ringR + 18, z0 + 3, 16)], W, H, 30)
  const t = THEMES[theme]
  const st = steps(n, 1500, 520)
  const order = [0, 3, 6, 1, 4, 7, 2, 5] // the file wanders rather than walks round
  const parts = []

  // the dial: a round plate, a dashed track, the hub's seat
  const dial = solid(cam, round(0, 0, R), round(0, 0, R - 2.2), 0, zTop)
  parts.push(el(dial.sil, "sil"), el(dial.crease, "lo nf"))
  parts.push(el(ringPath(cam, round(0, 0, 80), zTop), "dash lo"))
  parts.push(el(ringPath(cam, round(0, 0, 32), zTop), "lo nf"))

  // the pucks and the hub, back to front
  const rest = [3.5, 4.5, 3, 5, 3.5, 4, 3, 4.5]
  const items = Array.from({ length: n }, (_, i) => {
    const a = (i / n) * Math.PI * 2 - Math.PI / 2
    return { kind: "puck", i, x: ringR * Math.cos(a), y: ringR * Math.sin(a) }
  })
  items.push({ kind: "hub", x: 0, y: 0 })
  items.sort((a, b) => cam.depth(a.x, a.y) - cam.depth(b.x, b.y))
  for (const it of items) {
    if (it.kind === "hub") {
      // the hub is the fruit: a round body, a stem, a leaf
      const hub = solid(cam, round(0, 0, 22), round(0, 0, 20), zTop, zTop + 11)
      const stem = solid(cam, rrect(-3, -3, 3, 3, 1.5), null, zTop + 11, zTop + 16)
      const leaf = solid(cam, rrect(3, -9, 15, -3, 3), rrect(4, -8, 14, -4, 2), zTop + 11, zTop + 13)
      parts.push(el(hub.sil, "sil"), el(hub.crease, "lo nf"), el(leaf.sil, "sil"), el(leaf.crease, "lo nf"), el(stem.sil, "sil"))
      continue
    }
    const ring = rrect(it.x - 12, it.y - 12, it.x + 12, it.y + 12, 7)
    const inner = rrect(it.x - 10.6, it.y - 10.6, it.x + 10.6, it.y + 10.6, 5.6)
    const low = solid(cam, ring, inner, zTop, zTop + rest[it.i])
    const high = solid(cam, ring, inner, zTop, zTop + 17)
    const chosen = (j) => order[j] === it.i
    const morph = (key) => `<animate attributeName="d" values="${st.values((j) => (chosen(j) ? high[key] : low[key]))}" keyTimes="${st.keyTimes}" calcMode="spline" keySplines="${st.keySplines}" dur="${st.dur}ms" repeatCount="indefinite"/>`
    const stroke = `<animate attributeName="stroke" values="${st.values((j) => (chosen(j) ? t.hi : t.edge))}" keyTimes="${st.keyTimes}" calcMode="discrete" dur="${st.dur}ms" repeatCount="indefinite"/>`
    const first = order[n - 1] === it.i
    parts.push(`<path d="${first ? high.sil : low.sil}" class="${first ? "hi" : "sil"}">${morph("sil")}${stroke}</path>`)
    parts.push(`<path d="${first ? high.crease : low.crease}" class="lo nf">${morph("crease")}</path>`)
  }

  // the file: a sheet with three lines, hovering over the chosen format
  const sheet = []
  sheet.push(el(line(cam, [0, 0, zTop + 17], [0, 0, z0 - 1]), "dash"))
  sheet.push(plate(cam, -15, -19, 15, 19, 3, 1, z0, z0 + 2.4))
  for (const [y, len] of [[-6, 16], [1, 12], [8, 15]]) sheet.push(el(line(cam, [-9, y, z0 + 2.4], [-9 + len, y, z0 + 2.4]), "lo"))
  const origin = cam.P(0, 0, 0)
  const offset = (j) => {
    const a = (order[j] / n) * Math.PI * 2 - Math.PI / 2
    const p = cam.P(ringR * Math.cos(a), ringR * Math.sin(a), 0)
    return `${r2(p[0] - origin[0])} ${r2(p[1] - origin[1])}`
  }
  parts.push(
    `<g transform="translate(${offset(n - 1)})"><animateTransform attributeName="transform" type="translate" values="${st.values(offset)}" keyTimes="${st.keyTimes}" calcMode="spline" keySplines="${st.keySplines}" dur="${st.dur}ms" repeatCount="indefinite"/>${sheet.join("")}</g>`
  )
  return document(W, H, "A file hovers over the conversion dial; the format under it rises to meet it", theme, parts.join("\n  "))
}

/* ---- 2. cutout: the subject lifts off; the background sinks away ------- */

function cutout(theme) {
  const W = 640
  const H = 440
  const P0 = { x0: -84, y0: -60, x1: 84, y1: 60 }
  const lifted = 40
  const zp = 4.5
  const fruitTop = zp + 31 + lifted
  const cam = framed(
    [
      [P0.x0, P0.y0, 0],
      [P0.x1, P0.y1, 0],
      [P0.x1, P0.y0, 0],
      [P0.x0, P0.y1, 0],
      ...circle(0, 6, 27, fruitTop, 12),
    ],
    W,
    H,
    34
  )
  const t = THEMES[theme]
  const dur = 8000
  const kt = [0, 1500, 2600, 5600, 6700, dur].map((ms) => r2(ms / dur)).join(";")
  const ks = [LIN, EASE, LIN, EASE, LIN].join(";")
  const anim = (attr, a, b) => `<animate attributeName="${attr}" values="${a};${a};${b};${b};${a};${a}" keyTimes="${kt}" calcMode="spline" keySplines="${ks}" dur="${dur}ms" repeatCount="indefinite"/>`
  const parts = []

  // the photo: a plate
  parts.push(plate(cam, P0.x0, P0.y0, P0.x1, P0.y1, 8, 1.6, 0, zp))

  // the transparency grid, under everything, fading in as the scene goes
  const grid = []
  for (let gx = -72; gx <= 72; gx += 12) {
    for (let gy = -48; gy <= 48; gy += 12) {
      const on = (Math.round(gx / 12) + Math.round(gy / 12)) % 2 === 0
      grid.push(dot(cam, gx, gy, zp, on ? "dot m" : "dot off", 2))
    }
  }
  parts.push(`<g opacity="0">${grid.join("")}${anim("opacity", 0, 1)}</g>`)

  // the scene around the subject: stones and a low wall that sink away,
  // and the subject itself, a tangerine, which lifts off; back to front
  const scene = [
    { x: -62, y: -40, r: 7, h: 9 },
    { x: -40, y: 32, r: 9, h: 12 },
    { x: 56, y: -34, r: 6, h: 7 },
    { x: 64, y: 30, r: 10, h: 6 },
    { x: 28, y: 44, r: 5, h: 10 },
    { x: -70, y: 4, r: 5, h: 5 },
    { x: 40, y: -6, r: 4, h: 8 },
    { wall: true, x: -10, y: -46 },
    { fruit: true, x: 0, y: 6 },
  ]
  scene.sort((a, b) => cam.depth(a.x, a.y) - cam.depth(b.x, b.y))
  for (const it of scene) {
    if (it.fruit) {
      const lift = cam.up(lifted)
      const fruit = solid(cam, round(0, 6, 27), round(0, 6, 24.5), zp, zp + 24)
      const leaf = solid(cam, rrect(2, -14, 20, -5, 4.5), rrect(3.4, -12.6, 18.6, -6.4, 3), zp + 24, zp + 27)
      const stem = solid(cam, rrect(-3, -6, 3, 0, 2), null, zp + 24, zp + 31)
      const stroke = anim("stroke", t.edge, t.hi)
      // its footprint stays behind, dashed, while it is lifted
      parts.push(`<g opacity="0">${el(ringPath(cam, round(0, 6, 27), zp), "dash")}${anim("opacity", 0, 1)}</g>`)
      parts.push(
        `<g><animateTransform attributeName="transform" type="translate" values="0 0;0 0;0 ${-lift};0 ${-lift};0 0;0 0" keyTimes="${kt}" calcMode="spline" keySplines="${ks}" dur="${dur}ms" repeatCount="indefinite"/>` +
          `<path d="${fruit.sil}" class="sil">${stroke}</path>${el(fruit.crease, "lo nf")}` +
          `<path d="${leaf.sil}" class="sil">${stroke}</path>${el(leaf.crease, "lo nf")}` +
          `<path d="${stem.sil}" class="sil">${stroke}</path></g>`
      )
      continue
    }
    const ring = it.wall ? rrect(-58, -52, 30, -44, 3) : round(it.x, it.y, it.r, 6)
    const inner = it.wall ? rrect(-57, -51, 29, -45, 2) : round(it.x, it.y, it.r - 1.2, 6)
    const h = it.wall ? 14 : it.h
    const up = solid(cam, ring, inner, zp, zp + h)
    const flat = solid(cam, ring, inner, zp, zp + 0.01)
    parts.push(`<g><path d="${up.sil}" class="sil">${anim("d", up.sil, flat.sil)}</path><path d="${up.crease}" class="lo nf">${anim("d", up.crease, flat.crease)}</path>${anim("opacity", 1, 0)}</g>`)
  }
  return document(W, H, "Background removal: the subject lifts off the photo, the scene sinks away, the background becomes transparent", theme, parts.join("\n  "))
}

/* ---- 3. press: three files shrink to a fraction of their height -------- */

function press(theme) {
  const W = 640
  const H = 440
  const tray = { x0: -98, y0: -38, x1: 98, y1: 38 }
  const files = [
    { x0: -82, y0: -20, x1: -42, y1: 20, r: 6, h: 54, low: 22, mark: "photo" },
    { x0: -26, y0: -20, x1: 26, y1: 20, r: 6, h: 66, low: 18, mark: "film" },
    { x0: 42, y0: -23, x1: 80, y1: 23, r: 3, h: 46, low: 26, mark: "page" },
  ]
  const zt = 5
  const cam = framed(
    [
      [tray.x0, tray.y0, 0],
      [tray.x1, tray.y1, 0],
      [tray.x1, tray.y0, 0],
      [tray.x0, tray.y1, 0],
      ...files.flatMap((f) => [
        [f.x0, f.y0, zt + f.h],
        [f.x1, f.y0, zt + f.h],
        [f.x0, f.y1, zt + f.h],
      ]),
    ],
    W,
    H,
    40
  )
  const dur = 7000
  const parts = []

  // the tray: the compressor, and the one bright edge
  const base = solid(cam, rrect(tray.x0, tray.y0, tray.x1, tray.y1, 12, 6), rrect(tray.x0 + 2, tray.y0 + 2, tray.x1 - 2, tray.y1 - 2, 10, 6), 0, zt)
  parts.push(el(base.sil, "hi"), el(base.crease, "lo nf"))

  files.forEach((f, i) => {
    const ring = rrect(f.x0, f.y0, f.x1, f.y1, f.r)
    const inner = rrect(f.x0 + 1.6, f.y0 + 1.6, f.x1 - 1.6, f.y1 - 1.6, Math.max(0.5, f.r - 1.6))
    const tall = solid(cam, ring, inner, zt, zt + f.h)
    const short = solid(cam, ring, inner, zt, zt + f.low)
    const t0 = 900 + i * 260
    const kt = [0, t0, t0 + 900, 4600 + i * 120, 5600 + i * 120, dur].map((ms) => r2(ms / dur)).join(";")
    const ks = [LIN, EASE, LIN, EASE, LIN].join(";")
    const morph = (k) => `<animate attributeName="d" values="${tall[k]};${tall[k]};${short[k]};${short[k]};${tall[k]};${tall[k]}" keyTimes="${kt}" calcMode="spline" keySplines="${ks}" dur="${dur}ms" repeatCount="indefinite"/>`
    // the size it was, dashed, behind the size it is
    parts.push(el(tall.sil, "dash"))
    parts.push(`<path d="${tall.sil}" class="sil">${morph("sil")}</path><path d="${tall.crease}" class="lo nf">${morph("crease")}</path>`)
    // what it is, as marks on its top, riding down with it
    const z = zt + f.h
    const cx = (f.x0 + f.x1) / 2
    const cy = (f.y0 + f.y1) / 2
    const marks = []
    if (f.mark === "photo") {
      marks.push(`<path d="${pathOf([[f.x0 + 6, f.y1 - 8], [cx - 4, cy - 2], [cx + 3, cy + 5], [f.x1 - 6, f.y0 + 10]].map(([x, y]) => cam.P(x, y, z)), false)}" class="sil nf"/>`)
      marks.push(dot(cam, f.x1 - 10, f.y1 - 10, z, "dot m", 2.4))
    } else if (f.mark === "film") {
      for (let x = f.x0 + 6; x <= f.x1 - 5; x += 7) marks.push(dot(cam, x, f.y0 + 5, z, "dot off", 1.6), dot(cam, x, f.y1 - 5, z, "dot off", 1.6))
      marks.push(el(ringPath(cam, rrect(f.x0 + 6, f.y0 + 11, f.x1 - 6, f.y1 - 11, 2), z), "lo nf"))
    } else {
      for (const [k, len] of [[0, 22], [1, 16], [2, 24], [3, 12]]) marks.push(el(line(cam, [f.x0 + 7, f.y0 + 10 + k * 8, z], [f.x0 + 7 + len, f.y0 + 10 + k * 8, z]), "lo"))
    }
    const down = cam.up(f.h - f.low)
    parts.push(`<g><animateTransform attributeName="transform" type="translate" values="0 0;0 0;0 ${down};0 ${down};0 0;0 0" keyTimes="${kt}" calcMode="spline" keySplines="${ks}" dur="${dur}ms" repeatCount="indefinite"/>${marks.join("")}</g>`)
  })
  return document(W, H, "Compression: a photo, a video and a document shrink to a fraction of their size; the dashed outline is the size they were", theme, parts.join("\n  "))
}

/* ---- 4. local: files circle the Mac inside a boundary they never cross - */

function local(theme) {
  const W = 640
  const H = 440
  const orbit = 118
  const fence = 146
  const bx = 62
  const by = 42
  const tilt = (14 * Math.PI) / 180
  const lidH = 84
  const th = 3
  const hinge = -by + 2
  // lid point: (x, height along the lid, depth through it) → 3D
  const L = (x, w, d = 0) => [x, hinge - w * Math.sin(tilt) + d * Math.cos(tilt), 5 + w * Math.cos(tilt) + d * Math.sin(tilt)]
  const cam = framed([...circle(0, 0, fence + 9, 0, 32), L(-bx, lidH, -th), L(bx, lidH, -th)], W, H, 26)
  const parts = []

  // the boundary on the ground
  parts.push(el(ringPath(cam, round(0, 0, fence, 18), 0), "dash"))
  parts.push(el(ringPath(cam, round(0, 0, fence + 9, 18), 0), "dash lo"))

  // files on their round: drawn first, so the Mac hides the far side of it
  const zf = 16
  const c = cam.P(0, 0, zf)
  const rx = r2(cam.S * orbit)
  const ry = r2(cam.S * orbit * cam.k)
  const path = `M${r2(c[0] + rx)} ${c[1]}A${rx} ${ry} 0 1 1 ${r2(c[0] - rx)} ${c[1]}A${rx} ${ry} 0 1 1 ${r2(c[0] + rx)} ${c[1]}`
  const shift = (d) => d.replace(/(-?\d+(?:\.\d+)?) (-?\d+(?:\.\d+)?)/g, (_, x, y) => `${r2(Number(x) - c[0])} ${r2(Number(y) - c[1])}`)
  const s = solid(cam, rrect(-9, -12, 9, 12, 2.5), rrect(-8, -11, 8, 11, 1.5), zf, zf + 2)
  const lines = [line(cam, [-5, -5, zf + 2], [5, -5, zf + 2]), line(cam, [-5, 0, zf + 2], [3, 0, zf + 2]), line(cam, [-5, 5, zf + 2], [4, 5, zf + 2])]
  const sheet = `<path d="${shift(s.sil)}" class="sil"/><path d="${shift(s.crease)}" class="lo nf"/>${lines.map((d) => `<path d="${shift(d)}" class="lo"/>`).join("")}`
  for (let i = 0; i < 4; i += 1) {
    parts.push(`<g>${sheet}<animateMotion dur="16s" begin="${-i * 4}s" repeatCount="indefinite" path="${path}"/></g>`)
  }

  // the Mac: a base with a keyboard deck and a trackpad, and a lid leaning back
  parts.push(plate(cam, -bx, -by, bx, by, 8, 1.6, 0, 5))
  parts.push(el(ringPath(cam, rrect(-bx + 10, -by + 8, bx - 10, 6, 3), 5), "lo nf"))
  for (let row = 0; row < 4; row += 1) {
    parts.push(el(line(cam, [-bx + 14, -by + 14 + row * 9, 5], [bx - 14, -by + 14 + row * 9, 5]), "lo"))
  }
  parts.push(el(ringPath(cam, rrect(-18, 14, 18, 34, 3), 5), "lo nf"))
  const outline = rrect(-bx + 2, 0, bx - 2, lidH, 7, 4)
  const back = outline.map((q) => cam.P(...L(q.u, q.v, -th)))
  const front = outline.map((q) => cam.P(...L(q.u, q.v, 0)))
  parts.push(`<path d="${pathOf(hull([...back, ...front]))}" class="sil"/>`)
  parts.push(`<path d="${pathOf(rrect(-bx + 3.5, 1.5, bx - 3.5, lidH - 1.5, 5.6, 4).map((q) => cam.P(...L(q.u, q.v, 0))))}" class="lo nf"/>`)
  // the display: the one bright thing, where the work happens
  parts.push(`<path d="${pathOf(rrect(-bx + 9, 8, bx - 9, lidH - 8, 3, 3).map((q) => cam.P(...L(q.u, q.v, 0))))}" class="hi nf"/>`)
  parts.push(`<path d="${pathOf(rrect(-9, lidH - 8, 9, lidH - 3, 2, 2).map((q) => cam.P(...L(q.u, q.v, 0))))}" class="sil"/>`)

  return document(W, H, "Everything stays on your Mac: files circle the laptop inside a boundary they never cross", theme, parts.join("\n  "))
}

for (const theme of ["light", "dark"]) {
  for (const [name, draw] of [
    ["drop", drop],
    ["cutout", cutout],
    ["press", press],
    ["local", local],
  ]) {
    const content = draw(theme)
    writeFileSync(join(OUT, `hairline-${name}-${theme}.svg`), content)
    console.log(`docs/readme/hairline-${name}-${theme}.svg  ${(content.length / 1024).toFixed(1)} kB`)
  }
}
