/*
 * Animated illustrations for the README.
 *
 *   node scripts/readme/build.mjs   →   docs/readme/<name>-light.svg, <name>-dark.svg
 *
 * Transparent background: the README picks the light or dark file with
 * <picture> + prefers-color-scheme, so each one sits on GitHub's own page.
 * No dependencies. Motion is CSS keyframes (floating, pressing) and SMIL
 * (highlights, progress, morphing), both of which run when GitHub shows an SVG,
 * and both of which stop under prefers-reduced-motion where the browser allows.
 */

import { mkdirSync, writeFileSync } from "fs"
import { dirname, join } from "path"
import { fileURLToPath } from "url"

const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "docs", "readme")
mkdirSync(OUT, { recursive: true })

/* ---- palettes --------------------------------------------------------- */

/** Each colour: [ink on a tile, lit side face, shaded side face]. */
const THEMES = {
  light: {
    ink: "#ffffff",
    card: "#fffdf8",
    line: "#a3a593",
    text: "#24251e",
    muted: "#6c6e62",
    tagline: "#45473c",
    grid: "#4d503f",
    gridOpacity: 0.07,
    shadow: "#2b2c1f",
    shadowScale: 0.4,
    glowScale: 0.45,
    glass: "#ffffff",
    glassEdge: "#24251e",
    glassEdgeOpacity: 0.14,
    paper: ["#fbf3e6", "#fde2cc"],
    orange: ["#e04f00", "#ffa26b", "#f36a1d"],
    lime: ["#4d7c0f", "#b5dd85", "#7fae3a"],
    lemon: ["#9a6700", "#f6d679", "#d9a92a"],
    grape: ["#6d3fc0", "#c3adfb", "#8f6cf0"],
    berry: ["#c0266d", "#f5a3c8", "#d9508f"],
    sky: ["#0b6aa8", "#9fd0f3", "#3f97d6"],
    mint: ["#0f766e", "#97dccf", "#38a596"],
    stone: ["#78776c", "#dcdbd2", "#b0afa3"],
  },
  dark: {
    ink: "#12161d",
    card: "#151a22",
    line: "#868b78",
    text: "#ecede3",
    muted: "#9b9f90",
    tagline: "#c8cabd",
    grid: "#d0d3bf",
    gridOpacity: 0.07,
    shadow: "#000000",
    shadowScale: 1,
    glowScale: 0.8,
    glass: "#1b212b",
    glassEdge: "#ffffff",
    glassEdgeOpacity: 0.12,
    paper: ["#191c22", "#2a1e17"],
    orange: ["#ff8a4c", "#e8622a", "#a8420f"],
    lime: ["#a8de73", "#5f9a2a", "#3f6a17"],
    lemon: ["#f2c95e", "#c08a1c", "#86600f"],
    grape: ["#b9a2ff", "#7254d8", "#4b37a8"],
    berry: ["#f591c2", "#c24f8a", "#8c3062"],
    sky: ["#82c6f5", "#2f7fc0", "#1d5687"],
    mint: ["#72d9c6", "#2a9a8a", "#1a685e"],
    stone: ["#a9a79c", "#56554c", "#3a3932"],
  },
}

// The drawing functions read these; `useTheme` swaps them before each build.
let T
/** A hue as { s: strong ink, lit: lit face, shade: shaded face }. */
const hue = (name) => ({ s: T[name][0], lit: T[name][1], shade: T[name][2] })

function useTheme(name) {
  T = { ...THEMES[name], name }
}

const MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"
const SANS = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', Inter, 'Segoe UI', Helvetica, Arial, sans-serif"
const EASE = "0.32 0.72 0 1"
const LIN = "0 0 1 1"

const esc = (s) => String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")

/* ---- isometric helpers ------------------------------------------------ */

const C = Math.cos(Math.PI / 6)
const S = 0.5
const r = (n) => Math.round(n * 100) / 100

/** Screen point of iso (x right-down, y left-down, z up). */
function P(o, x, y, z = 0) {
  return [r(o[0] + (x - y) * C), r(o[1] + (x + y) * S - z)]
}

const pts = (list) => list.map((p) => p.join(",")).join(" ")

/** Matrix mapping local (u, v) on the plane at (x0, y0, z) to the screen. */
function plane(o, x0, y0, z) {
  const [ex, ey] = P(o, x0, y0, z)
  return `matrix(${r(C)} ${S} ${r(-C)} ${S} ${ex} ${ey})`
}

/** A slab: top face at height z, `t` thick. Returns the two sides and the top. */
function slab(o, { x, y, z, w, h, t }, { top, right, left, stroke = "none", strokeOpacity = 1 }) {
  const a = P(o, x, y, z)
  const b = P(o, x + w, y, z)
  const c = P(o, x + w, y + h, z)
  const d = P(o, x, y + h, z)
  const b2 = P(o, x + w, y, z - t)
  const c2 = P(o, x + w, y + h, z - t)
  const d2 = P(o, x, y + h, z - t)
  return [
    `<polygon points="${pts([b, c, c2, b2])}" fill="${right}"/>`,
    `<polygon points="${pts([d, c, c2, d2])}" fill="${left}"/>`,
    `<polygon points="${pts([a, b, c, d])}" fill="${top}" stroke="${stroke}" stroke-opacity="${strokeOpacity}" stroke-width="1.2" stroke-linejoin="round"/>`,
  ].join("")
}

/** Soft shadow under a slab, on the plane at height `ground`. */
function shadow(o, { x, y, w, h }, ground, id = "soft", opacity = 0.45) {
  const q = [P(o, x, y, ground), P(o, x + w, y, ground), P(o, x + w, y + h, ground), P(o, x, y + h, ground)]
  return `<polygon points="${pts(q)}" fill="${T.shadow}" opacity="${r(opacity * T.shadowScale)}" filter="url(#${id})"/>`
}

/** A cylinder (a round plate) of radius R centred at iso (cx, cy), top at z. */
function disc(o, { cx, cy, z, R, t }, { top, lit, shade, id, stroke = "none", strokeOpacity = 1 }) {
  const [x, y] = P(o, cx, cy, z)
  const rx = r(Math.SQRT2 * C * R)
  const ry = r(Math.SQRT2 * S * R)
  const side = `M${r(x - rx)} ${y}L${r(x - rx)} ${r(y + t)}A${rx} ${ry} 0 0 0 ${r(x + rx)} ${r(y + t)}L${r(x + rx)} ${y}Z`
  return [
    `<linearGradient id="${id}" x1="0" x2="1"><stop offset="0" stop-color="${shade}"/><stop offset=".6" stop-color="${lit}"/><stop offset="1" stop-color="${lit}"/></linearGradient>`,
    `<path d="${side}" fill="url(#${id})"/>`,
    `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" fill="${top}" stroke="${stroke}" stroke-opacity="${strokeOpacity}" stroke-width="1.2"/>`,
  ].join("")
}

/* ---- svg scaffolding -------------------------------------------------- */

function defs(width, height) {
  const glow = (id, name, strength) =>
    `<radialGradient id="${id}" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="${T[name][0]}" stop-opacity="${r(strength * T.glowScale)}"/><stop offset="1" stop-color="${T[name][0]}" stop-opacity="0"/></radialGradient>`
  return `
  <defs>
    ${glow("glowOrange", "orange", 0.42)}
    ${glow("glowLime", "lime", 0.3)}
    ${glow("glowGrape", "grape", 0.3)}
    ${glow("glowBerry", "berry", 0.26)}
    ${glow("glowSky", "sky", 0.26)}
    ${glow("glowLemon", "lemon", 0.28)}
    <radialGradient id="fadeGrad" cx=".5" cy=".5" r=".5"><stop offset=".35" stop-color="#fff" stop-opacity="1"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>
    <mask id="fade" maskUnits="userSpaceOnUse" x="0" y="0" width="${width}" height="${height}"><rect width="${width}" height="${height}" fill="url(#fadeGrad)"/></mask>
    <filter id="soft" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="9"/></filter>
    <filter id="softer" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="16"/></filter>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  </defs>`
}

const STYLE = `
  <style>
    .float { animation: float 6s ease-in-out infinite; }
    .float.d1 { animation-delay: -1.5s; }
    .float.d2 { animation-delay: -3s; }
    .float.d3 { animation-delay: -4.5s; }
    .breathe { animation: breathe 6s ease-in-out infinite; transform-box: fill-box; transform-origin: center; }
    .breathe.d1 { animation-delay: -1.5s; }
    .breathe.d2 { animation-delay: -3s; }
    .breathe.d3 { animation-delay: -4.5s; }
    .twinkle { animation: twinkle 4s ease-in-out infinite; }
    .drift { animation: drift 16s linear infinite; }
    .press { animation: press 6s cubic-bezier(.32,.72,0,1) infinite; }
    .press.k1 { animation-delay: 2s; }
    .press.k2 { animation-delay: 4s; }
    .run { animation: run 1.6s linear infinite; }
    @keyframes float { 0%, 100% { transform: translateY(0) } 50% { transform: translateY(-12px) } }
    @keyframes breathe { 0%, 100% { opacity: .5; transform: scale(1) } 50% { opacity: .3; transform: scale(.9) } }
    @keyframes twinkle { 0%, 100% { opacity: .15 } 50% { opacity: .75 } }
    @keyframes drift { from { transform: translateY(0) } to { transform: translateY(-640px) } }
    @keyframes press { 0%, 4% { transform: translateY(0) } 9%, 28% { transform: translateY(9px) } 34%, 100% { transform: translateY(0) } }
    @keyframes run { to { stroke-dashoffset: -20 } }
    @media (prefers-reduced-motion: reduce) { * { animation: none !important } }
  </style>`

function svg(width, height, body, title) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${width} ${height}" width="${width}" height="${height}" role="img" aria-label="${esc(title)}">
  <title>${esc(title)}</title>${defs(width, height)}${STYLE}
  ${body}
</svg>
`
}

/** Faint isometric grid over the whole canvas, faded at the edges. */
function isoGrid(width, height, step = 36) {
  const lines = []
  const span = width + height * 2
  for (let i = -span; i < span; i += step) {
    lines.push(`<line x1="${i}" y1="0" x2="${r(i + height / Math.tan(Math.PI / 6))}" y2="${height}"/>`)
    lines.push(`<line x1="${i}" y1="0" x2="${r(i - height / Math.tan(Math.PI / 6))}" y2="${height}"/>`)
  }
  return `<g mask="url(#fade)"><g stroke="${T.grid}" stroke-opacity="${T.gridOpacity}" stroke-width="1">${lines.join("")}</g></g>`
}

/** File extensions drifting up, like zest. */
function particles(width, height, count, seed = 1, avoid = null) {
  let s = seed
  const rand = () => {
    s = (s * 9301 + 49297) % 233280
    return s / 233280
  }
  const glyphs = [".png", "●", ".pdf", "+", ".mov", "·", ".heic", "◐", ".mp3", ".webp", "●", ".jpg"]
  const colors = ["orange", "lime", "grape", "lemon", "berry", "sky", "mint"]
  const out = []
  for (let i = 0; i < count; i += 1) {
    let x = r(rand() * width)
    const y = r(rand() * height + height * 0.2)
    if (avoid && x > avoid[0] && x < avoid[1]) x = r(avoid[1] + rand() * (width - avoid[1] - 30))
    const dur = r(12 + rand() * 14)
    const delay = r(-rand() * dur)
    out.push(
      `<g class="drift" style="animation-duration:${dur}s;animation-delay:${delay}s"><text x="${x}" y="${r(y + 640)}" font-family="${MONO}" font-size="${r(9 + rand() * 5)}" fill="${T[colors[i % colors.length]][0]}" class="twinkle" style="animation-delay:${r(-rand() * 4)}s">${glyphs[i % glyphs.length]}</text></g>`
    )
  }
  return out.join("")
}

/* ---- icons (16 × 16, stroked) ----------------------------------------- */

const ICONS = {
  image: "M3 2.5h10a1.5 1.5 0 0 1 1.5 1.5v8a1.5 1.5 0 0 1-1.5 1.5H3A1.5 1.5 0 0 1 1.5 12V4A1.5 1.5 0 0 1 3 2.5ZM2 11.5l3.8-3.8 2.7 2.7 1.7-1.7 3.8 3.3M11.4 5.6a.9.9 0 1 1-1.8 0a.9.9 0 1 1 1.8 0",
  video: "M3 3h10a1.5 1.5 0 0 1 1.5 1.5v7A1.5 1.5 0 0 1 13 13H3a1.5 1.5 0 0 1-1.5-1.5v-7A1.5 1.5 0 0 1 3 3ZM6.5 5.8 10.5 8l-4 2.2Z",
  audio: "M2.5 6.5v3M5 4.5v7M7.5 2.5v11M10 5v6M12.5 3.5v9M15 7v2",
  doc: "M4 1.5h5.5L13 5v9.5H4ZM9.5 1.5V5H13M6 8.2h5M6 10.6h5M6 13h3",
  subtitle: "M3 3h10a1.5 1.5 0 0 1 1.5 1.5v7A1.5 1.5 0 0 1 13 13H3a1.5 1.5 0 0 1-1.5-1.5v-7A1.5 1.5 0 0 1 3 3ZM4 9.2h5M10.5 9.2H12M4 11h3M8.5 11H12",
  archive: "M1.5 2.5h13v3h-13ZM2.5 5.5h11v8.5h-11ZM6.5 8h3",
  crop: "M4 1.5V12h10.5M1.5 4H12v10.5",
  trim: "M5.6 4.2a2 2 0 1 1-4 0a2 2 0 1 1 4 0M5.6 11.8a2 2 0 1 1-4 0a2 2 0 1 1 4 0M5.2 5.3 14 12.5M5.2 10.7 14 3.5",
  rotate: "M13.2 9A5.3 5.3 0 1 1 11.6 4.2M12 1.6v3h-3",
  resize: "M9.5 2.5h4v4M13.5 2.5 9 7M6.5 13.5h-4v-4M2.5 13.5 7 9",
  redact: "M3 3h10a1.5 1.5 0 0 1 1.5 1.5v7A1.5 1.5 0 0 1 13 13H3a1.5 1.5 0 0 1-1.5-1.5v-7A1.5 1.5 0 0 1 3 3ZM4 6.8h8v2.6H4Z",
  collage: "M2 2h5v5H2ZM9 2h5v5H9ZM2 9h5v5H2ZM9 9h5v5H9Z",
  edit: "M1.5 4.5h13M1.5 11.5h13M6.6 4.5a1.6 1.6 0 1 1-3.2 0a1.6 1.6 0 1 1 3.2 0M12.6 11.5a1.6 1.6 0 1 1-3.2 0a1.6 1.6 0 1 1 3.2 0",
  frame: "M3 1.5h10A1.5 1.5 0 0 1 14.5 3v10a1.5 1.5 0 0 1-1.5 1.5H3A1.5 1.5 0 0 1 1.5 13V3A1.5 1.5 0 0 1 3 1.5ZM5 4.5h6a.5.5 0 0 1 .5.5v6a.5.5 0 0 1-.5.5H5a.5.5 0 0 1-.5-.5V5a.5.5 0 0 1 .5-.5Z",
  speed: "M2.5 12A5.5 5.5 0 1 1 13.5 12M8 12l3-4.2",
  link: "M6.4 9.6l3.2-3.2M5.2 7.8 3.6 9.4a2.1 2.1 0 0 0 3 3L8.2 10.8M7.8 5.2 9.4 3.6a2.1 2.1 0 0 1 3 3L10.8 8.2",
  frames: "M1.5 5V3a1.5 1.5 0 0 1 1.5-1.5h2M11 1.5h2A1.5 1.5 0 0 1 14.5 3v2M14.5 11v2a1.5 1.5 0 0 1-1.5 1.5h-2M5 14.5H3A1.5 1.5 0 0 1 1.5 13v-2M10.5 8a2.5 2.5 0 1 1-5 0a2.5 2.5 0 1 1 5 0",
  split: "M3 3h10a1.5 1.5 0 0 1 1.5 1.5v7A1.5 1.5 0 0 1 13 13H3a1.5 1.5 0 0 1-1.5-1.5v-7A1.5 1.5 0 0 1 3 3ZM8 1.5v13",
  wave: "M1 8h2.2l1.5-3.6 2 7.2 2-9.2 2 10.4 1.6-4.8H15",
  bars: "M1.5 14.5h13M3.5 12V9M6.5 12V5M9.5 12V7M12.5 12V3",
  phones: "M2.5 10.5V8a5.5 5.5 0 0 1 11 0v2.5M2 10h2.6v4.5H2ZM11.4 10H14v4.5h-2.6Z",
  bleep: "M1.5 6h2.6L8 2.8v10.4L4.1 10H1.5ZM10.5 6l3.5 4M14 6l-3.5 4",
  merge: "M5.5 4.5H12v10H5.5ZM3.5 12V2h6.5",
  stack: "M3 5.5h10v8.5H3ZM4.5 3.5h7M6 1.5h4",
  splitdoc: "M4 1.5h5.5L13 5v9.5H4ZM9.5 1.5V5H13M1.5 8.5h3M6 8.5h1.5M9 8.5h1.5M12 8.5h2.5",
  compress: "M2 2l4 4M6 2.6V6H2.6M14 14l-4-4M10 13.4V10h3.4M14 2l-4 4M10 2.6V6h3.4M2 14l4-4M6 13.4V10H2.6",
  tag: "M1.8 2.8v4.4l7 7 5.4-5.4-7-7H2.8a1 1 0 0 0-1 1ZM5.6 5.2a.8.8 0 1 1-1.6 0a.8.8 0 1 1 1.6 0",
  folder: "M1.5 4.5a1 1 0 0 1 1-1h3.6l1.6 1.6h5.8a1 1 0 0 1 1 1v6.4a1 1 0 0 1-1 1h-11a1 1 0 0 1-1-1Z",
  copy: "M5.5 5.5h8.5v9H5.5ZM3 11.5V2h8",
  dup: "M5.5 5.5h9v9h-9ZM3 11V2.5h8.5M10 7.8v4.4M7.8 10h4.4",
  hash: "M6.4 1.8 5.2 14.2M11 1.8 9.8 14.2M2.6 5.6h11.4M2 10.4h11.4",
  wand: "M2 14 10.5 5.5M9 4l3 3M12.5 1.5v2M15 4h-2M14.2 2.3l-1.2 1.2",
  cutout: "M3 1.5h10A1.5 1.5 0 0 1 14.5 3v10a1.5 1.5 0 0 1-1.5 1.5H3A1.5 1.5 0 0 1 1.5 13V3A1.5 1.5 0 0 1 3 1.5ZM8 4.2c2 0 3.2 1.6 3.2 3.4S10 11.8 8 11.8 4.8 9.4 4.8 7.6 6 4.2 8 4.2Z",
  ocr: "M1.5 5V3a1.5 1.5 0 0 1 1.5-1.5h2M11 1.5h2A1.5 1.5 0 0 1 14.5 3v2M14.5 11v2a1.5 1.5 0 0 1-1.5 1.5h-2M5 14.5H3A1.5 1.5 0 0 1 1.5 13v-2M4.5 6h7M8 6v5",
  eye: "M1.5 8s2.4-4.5 6.5-4.5S14.5 8 14.5 8 12.1 12.5 8 12.5 1.5 8 1.5 8ZM10 8a2 2 0 1 1-4 0a2 2 0 1 1 4 0",
  watch: "M3 2.5h4l1.5 1.5h4.5v9.5H3ZM8 6.5v3l2 1.2",
  sparkle: "M8 1.5 9.4 6.6 14.5 8 9.4 9.4 8 14.5 6.6 9.4 1.5 8 6.6 6.6Z",
  check: "M3 8.5l3 3 7-7",
  lock: "M4 7.5h8v7H4ZM5.5 7.5V5a2.5 2.5 0 0 1 5 0v2.5",
  layers: "M8 2 14.5 5.5 8 9 1.5 5.5ZM1.5 8.5 8 12l6.5-3.5M1.5 11.5 8 15l6.5-3.5",
}

function icon(name, x, y, size, color, width = 1.5) {
  const k = r(size / 16)
  return `<path d="${ICONS[name]}" transform="translate(${r(x)} ${r(y)}) scale(${k})" fill="none" stroke="${color}" stroke-width="${r(width / k)}" stroke-linecap="round" stroke-linejoin="round"/>`
}

/* ---- the conversion wheel, drawn flat --------------------------------- */

/** An annular sector, angles in degrees clockwise from north. */
function sector(cx, cy, r0, r1, a0, a1) {
  const pt = (rad, a) => [r(cx + rad * Math.sin((a * Math.PI) / 180)), r(cy - rad * Math.cos((a * Math.PI) / 180))]
  const [x0, y0] = pt(r1, a0)
  const [x1, y1] = pt(r1, a1)
  const [x2, y2] = pt(r0, a1)
  const [x3, y3] = pt(r0, a0)
  const large = a1 - a0 > 180 ? 1 : 0
  return `M${x0} ${y0}A${r1} ${r1} 0 ${large} 1 ${x1} ${y1}L${x2} ${y2}A${r0} ${r0} 0 ${large} 0 ${x3} ${y3}Z`
}

/**
 * The radial picker: rounded segments around a hub, one selected. With
 * `step` the selection walks round the wheel; `active` pins it.
 */
function wheel({ cx, cy, r0, r1, labels, accent, fontSize = 12, step = 1.1, active = null, begin = 0, round = 7, gap = 3.2, textColor = T.text, base = T.glass, edge = T.glassEdge, edgeOpacity = T.glassEdgeOpacity, weight = 650 }) {
  const n = labels.length
  const span = 360 / n
  const dur = r(n * step)
  const out = []
  labels.forEach((label, i) => {
    const mid = i * span
    // Inset by the stroke so a round join gives the segment its soft corners.
    const inset = round / 2
    const d = sector(cx, cy, r0 + inset, r1 - inset, mid - span / 2 + gap / 2 + (inset * 180) / (Math.PI * r0 * 1.2), mid + span / 2 - gap / 2 - (inset * 180) / (Math.PI * r0 * 1.2))
    const values = Array.from({ length: n }, (_, k) => (k === i ? accent : base)).join(";")
    const textValues = Array.from({ length: n }, (_, k) => (k === i ? "#ffffff" : textColor)).join(";")
    const fill = active === null ? base : i === active ? accent : base
    const tfill = active === null ? textColor : i === active ? "#ffffff" : textColor
    const anim = (attr, vals) => (active === null ? `<animate attributeName="${attr}" values="${vals}" dur="${dur}s" begin="${begin}s" calcMode="discrete" repeatCount="indefinite"/>` : "")
    // A hairline edge under the glass, so a pale segment still reads on a pale page.
    out.push(`<path d="${d}" fill="none" stroke="${edge}" stroke-opacity="${edgeOpacity}" stroke-width="${round + 1.6}" stroke-linejoin="round"/>`)
    out.push(`<path d="${d}" fill="${fill}" stroke="${fill}" stroke-width="${round}" stroke-linejoin="round">${anim("fill", values)}${anim("stroke", values)}</path>`)
    const lr = (r0 + r1) / 2
    const lx = r(cx + lr * Math.sin((mid * Math.PI) / 180))
    const ly = r(cy - lr * Math.cos((mid * Math.PI) / 180) + fontSize * 0.36)
    out.push(`<text x="${lx}" y="${ly}" text-anchor="middle" font-family="${MONO}" font-size="${fontSize}" font-weight="${weight}" letter-spacing=".4" fill="${tfill}">${esc(label)}${anim("fill", textValues)}</text>`)
  })
  return out.join("")
}

/** The Open Tangerine mark: an orange disc, a ring of zest, a leaf. */
function mark(cx, cy, size, { color = T.orange[0], ring = "#ffffff" } = {}) {
  const k = size / 100
  const X = (n) => r(cx + (n - 50) * k)
  const Y = (n) => r(cy + (n - 50) * k)
  return [
    `<rect x="${X(4)}" y="${Y(4)}" width="${r(92 * k)}" height="${r(92 * k)}" rx="${r(22 * k)}" fill="${color}"/>`,
    `<ellipse cx="${X(50)}" cy="${Y(54)}" rx="${r(27 * k)}" ry="${r(26 * k)}" fill="none" stroke="${ring}" stroke-width="${r(5.5 * k)}"/>`,
    `<path d="M${X(49)} ${Y(27)}C${X(49)} ${Y(12)} ${X(66)} ${Y(12)} ${X(72)} ${Y(16)}C${X(70)} ${Y(27)} ${X(59)} ${Y(29)} ${X(49)} ${Y(27)}" fill="${ring}"/>`,
    `<path d="M${X(34)} ${Y(51)}Q${X(34)} ${Y(43)} ${X(43)} ${Y(39)}" fill="none" stroke="${ring}" stroke-width="${r(4 * k)}" stroke-linecap="round"/>`,
  ].join("")
}

/** The macOS pointer. */
function cursor(x, y, scale = 1) {
  return `<path transform="translate(${x} ${y}) scale(${scale})" d="M0 0V18.5L4.6 14.2 7.7 21.3 10.6 20 7.6 13H13.6Z" fill="#111111" stroke="#ffffff" stroke-width="1.4" stroke-linejoin="round"/>`
}

/** A keycap glyph with a word under it, drawn flat. */
function keyFace(w, h, glyph, word, color) {
  return [
    `<rect x="6" y="6" width="${w - 12}" height="${h - 12}" rx="10" fill="${T.card}" stroke="${color}" stroke-opacity=".5"/>`,
    `<text x="${w / 2}" y="${h / 2 + 8}" text-anchor="middle" font-family="${SANS}" font-size="34" font-weight="500" fill="${color}">${glyph}</text>`,
    `<text x="${w / 2}" y="${h - 16}" text-anchor="middle" font-family="${MONO}" font-size="9" letter-spacing="1.2" fill="${T.muted}">${word}</text>`,
  ].join("")
}

/* ---- tile contents (drawn flat, then projected) ---------------------- */

function photoThumb(w, h, { name = "photo.heic", size = "4.2 MB" } = {}) {
  const lime = hue("lime")
  const orange = hue("orange")
  const ih = h - 28
  return [
    `<rect width="${w}" height="${h}" fill="${T.card}"/>`,
    `<clipPath id="ph-${T.name}-${w}"><rect x="8" y="8" width="${w - 16}" height="${ih - 8}" rx="5"/></clipPath>`,
    `<g clip-path="url(#ph-${T.name}-${w})">`,
    `<rect x="8" y="8" width="${w - 16}" height="${ih - 8}" fill="${T.name === "light" ? "#fde9d8" : "#3a2a22"}"/>`,
    `<circle cx="${w - 34}" cy="26" r="9" fill="${orange.s}"/>`,
    `<path d="M0 ${ih}L${w * 0.32} ${ih * 0.45}L${w * 0.55} ${ih * 0.8}L${w * 0.7} ${ih * 0.6}L${w} ${ih}Z" fill="${lime.shade}"/>`,
    `<path d="M0 ${ih}L${w * 0.2} ${ih * 0.7}L${w * 0.42} ${ih}Z" fill="${lime.lit}"/>`,
    `</g>`,
    `<text x="10" y="${h - 9}" font-family="${MONO}" font-size="10" fill="${T.text}">${name}</text>`,
    `<text x="${w - 10}" y="${h - 9}" text-anchor="end" font-family="${MONO}" font-size="9" fill="${T.muted}">${size}</text>`,
  ].join("")
}

function videoThumb(w, h, { name = "clip.mov", size = "64 MB" } = {}) {
  const grape = hue("grape")
  const ih = h - 28
  const holes = []
  for (let x = 14; x < w - 14; x += 12) {
    holes.push(`<rect x="${x}" y="11" width="6" height="4" rx="1" fill="${T.card}" opacity=".7"/><rect x="${x}" y="${ih - 7}" width="6" height="4" rx="1" fill="${T.card}" opacity=".7"/>`)
  }
  return [
    `<rect width="${w}" height="${h}" fill="${T.card}"/>`,
    `<rect x="8" y="8" width="${w - 16}" height="${ih - 8}" rx="5" fill="${grape.shade}"/>`,
    holes.join(""),
    `<path d="M${w / 2 - 7} ${ih / 2 - 6}L${w / 2 + 9} ${ih / 2 + 4}L${w / 2 - 7} ${ih / 2 + 14}Z" fill="#ffffff"/>`,
    `<text x="10" y="${h - 9}" font-family="${MONO}" font-size="10" fill="${T.text}">${name}</text>`,
    `<text x="${w - 10}" y="${h - 9}" text-anchor="end" font-family="${MONO}" font-size="9" fill="${T.muted}">${size}</text>`,
  ].join("")
}

function pdfThumb(w, h, { name = "report.pdf" } = {}) {
  const lemon = hue("lemon")
  const lines = []
  for (let i = 0; i < 6; i += 1) {
    lines.push(`<rect x="16" y="${30 + i * 11}" width="${[60, 48, 64, 40, 56, 30][i] * ((w - 32) / 68)}" height="4" rx="2" fill="${T.line}" opacity=".45"/>`)
  }
  return [
    `<rect width="${w}" height="${h}" fill="${T.card}"/>`,
    `<rect x="12" y="12" width="${w - 24}" height="${h - 24}" rx="3" fill="none" stroke="${T.line}" stroke-opacity=".5"/>`,
    `<rect x="16" y="16" width="30" height="10" rx="2" fill="${lemon.s}"/>`,
    `<text x="31" y="24" text-anchor="middle" font-family="${MONO}" font-size="7.5" font-weight="700" fill="${T.card}">PDF</text>`,
    lines.join(""),
    `<text x="${w / 2}" y="${h - 18}" text-anchor="middle" font-family="${MONO}" font-size="9.5" fill="${T.text}">${name}</text>`,
  ].join("")
}

/** A projected, floating tile with its shadow. */
function tile(o, box, content, colors, { float = "", ground = 0 } = {}) {
  const { x, y, z, w, h, t = 10 } = box
  return `
    <g class="breathe ${float.replace("float", "").trim()}">${shadow(o, { x: x + 6, y: y + 10, w, h }, ground, "soft", 0.55)}</g>
    <g class="${float}">
      ${slab(o, { x, y, z, w, h, t }, { top: T.ink, right: colors.lit, left: colors.shade })}
      <g transform="${plane(o, x, y, z)}">
        <rect width="${w}" height="${h}" fill="${T.ink}"/>
        ${content(w, h)}
      </g>
      <polygon points="${pts([P(o, x, y, z), P(o, x + w, y, z), P(o, x + w, y + h, z), P(o, x, y + h, z)])}" fill="none" stroke="${colors.s}" stroke-opacity=".3"/>
    </g>`
}

/** A pill of text with a dashed outline, like the reference chips. */
function chip(x, y, label, color, { size = 14, pad = 15, h = 34 } = {}) {
  const w = r(label.length * size * 0.615 + pad * 2)
  return { w, svg: `<g transform="translate(${r(x)} ${r(y)})"><rect width="${w}" height="${h}" rx="7" fill="${color}" fill-opacity=".08" stroke="${color}" stroke-opacity=".7" stroke-dasharray="2 4"/><text x="${pad}" y="${r(h / 2 + size * 0.36)}" font-family="${MONO}" font-size="${size}" fill="${color}">${esc(label)}</text></g>` }
}

function chips(x, y, list, opts) {
  let cx = x
  return list
    .map(([label, color]) => {
      const c = chip(cx, y, label, color, opts)
      cx += c.w + 12
      return c.svg
    })
    .join("")
}

/* ---- 1. hero ---------------------------------------------------------- */

function hero() {
  const W = 1280
  const H = 640
  const o = [935, 262]
  const R = 150
  const z = 46
  const orange = hue("orange")
  const labels = ["JPEG", "PNG", "WEBP", "HEIC", "PDF", "TIFF", "AVIF", "BMP"]
  const hubR = 58
  const body = `
    ${isoGrid(W, H)}
    <ellipse cx="930" cy="360" rx="330" ry="280" fill="url(#glowOrange)"/>
    <ellipse cx="300" cy="480" rx="280" ry="150" fill="url(#glowLime)"/>
    <ellipse cx="1150" cy="140" rx="200" ry="110" fill="url(#glowGrape)"/>
    ${particles(W, H, 26, 7, [40, 640])}

    <!-- the wheel: a round plate, its segments, the hub -->
    <ellipse cx="955" cy="${366 + 62}" rx="200" ry="92" fill="${T.shadow}" opacity="${r(0.5 * T.shadowScale)}" filter="url(#softer)"/>
    ${disc(o, { cx: R, cy: R, z, R, t: 18 }, { top: T.ink, lit: orange.lit, shade: orange.shade, id: `wheelSide-${T.name}`, stroke: orange.s, strokeOpacity: 0.35 })}
    <g transform="${plane(o, 0, 0, z)}">
      <circle cx="${R}" cy="${R}" r="${R - 3}" fill="none" stroke="${T.line}" stroke-opacity=".35" stroke-dasharray="2 5"/>
      ${wheel({ cx: R, cy: R, r0: 66, r1: 142, labels, accent: orange.s, fontSize: 14, step: 1.1, round: 9, gap: 4 })}
    </g>
    ${disc(o, { cx: R, cy: R, z: z + 14, R: hubR, t: 14 }, { top: T.ink, lit: orange.lit, shade: orange.shade, id: `hubSide-${T.name}` })}
    <g transform="${plane(o, R - hubR, R - hubR, z + 14)}">
      <circle cx="${hubR}" cy="${hubR}" r="${hubR - 8}" fill="none" stroke="${orange.s}" stroke-opacity=".25"/>
      ${mark(hubR, hubR, 54, { color: orange.s })}
    </g>

    <!-- files hovering over the wheel -->
    ${tile(o, { x: 65, y: 346, z: 60, w: 110, h: 80, t: 8 }, (w, h) => videoThumb(w, h), hue("grape"), { float: "float d2", ground: 0 })}
    ${tile(o, { x: 120, y: -115, z: 130, w: 100, h: 120, t: 7 }, (w, h) => pdfThumb(w, h), hue("lemon"), { float: "float d3", ground: 0 })}
    <g class="float d1">
      ${tile(o, { x: -56, y: 59, z: 170, w: 130, h: 96, t: 8 }, (w, h) => photoThumb(w, h), hue("lime"))}
      ${cursor(906, 172, 1.25)}
    </g>
    ${tile(o, { x: 336, y: 178, z: 40, w: 124, h: 58, t: 7 }, (w, h) => outputFace(w, h), hue("lime"), { float: "float d1", ground: 0 })}

    <!-- left: words -->
    <g font-family="${SANS}">
      <text x="72" y="160" font-family="${MONO}" font-size="15" letter-spacing="4" fill="${orange.s}">MACOS · FILE CONVERTER · TOOLBOX</text>
      <text x="66" y="262" font-size="104" font-weight="800" fill="${T.text}" letter-spacing="-4">Open</text>
      <text x="66" y="360" font-size="104" font-weight="800" fill="${orange.s}" letter-spacing="-4">Tangerine</text>
      <text x="72" y="418" font-size="27" fill="${T.tagline}">Drag a file. Pick a format.</text>
      <text x="72" y="454" font-size="27" fill="${T.tagline}">It never leaves your Mac.</text>
    </g>
    ${chips(72, 492, [
      ["176 routes", orange.s],
      ["26 tools", T.lime[0]],
      ["batch", T.grape[0]],
      ["on-device", T.mint[0]],
    ])}
    <g font-family="${MONO}" font-size="14" fill="${T.muted}">
      <text x="72" y="578">photo.heic  <tspan fill="${orange.s}">⇧ drag → PNG</tspan>  <tspan fill="${T.lime[0]}">✓ photo.png</tspan></text>
    </g>`
  return svg(W, H, body, "Open Tangerine — a native macOS file converter: drag a file, pick a format, it never leaves your Mac")
}

/** The result card: a check that draws itself, the new file name. */
function outputFace(w, h) {
  const lime = hue("lime")
  return [
    `<rect width="${w}" height="${h}" fill="${T.card}"/>`,
    `<circle cx="22" cy="${h / 2}" r="12" fill="${lime.s}" fill-opacity=".14" stroke="${lime.s}" stroke-opacity=".6"/>`,
    `<path d="M16 ${h / 2}l4.5 4.5 8-8.5" fill="none" stroke="${lime.s}" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" stroke-dasharray="20" stroke-dashoffset="20"><animate attributeName="stroke-dashoffset" values="20;20;0;0;20" keyTimes="0;.2;.3;.92;1" dur="8.8s" repeatCount="indefinite"/></path>`,
    `<text x="42" y="${h / 2 - 3}" font-family="${MONO}" font-size="10.5" fill="${T.text}">photo.png</text>`,
    `<text x="42" y="${h / 2 + 11}" font-family="${MONO}" font-size="8.5" fill="${T.muted}">saved beside</text>`,
  ].join("")
}

/* ---- 2. workflow: select → drag + shift → saved ----------------------- */

/** A Finder window's chrome: traffic lights, a title, a hairline. */
function windowChrome(w, title) {
  return [
    `<circle cx="16" cy="16" r="4" fill="#ff5f57"/><circle cx="30" cy="16" r="4" fill="#febc2e"/><circle cx="44" cy="16" r="4" fill="#28c840"/>`,
    `<text x="${w / 2}" y="20.5" text-anchor="middle" font-family="${SANS}" font-size="11.5" font-weight="600" fill="${T.muted}">${title}</text>`,
    `<line x1="0" y1="32" x2="${w}" y2="32" stroke="${T.line}" stroke-opacity=".3"/>`,
  ].join("")
}

function finderFace(w, h) {
  const rows = [
    ["image", "photo.heic", "4.2 MB", "lime", true],
    ["video", "clip.mov", "64 MB", "grape"],
    ["doc", "notes.txt", "8 KB", "lemon"],
    ["audio", "voice.wav", "12 MB", "berry"],
  ]
  const orange = hue("orange")
  const out = [`<rect width="${w}" height="${h}" fill="${T.card}"/>`, windowChrome(w, "Downloads")]
  rows.forEach(([ic, name, size, color, sel], i) => {
    const y = 40 + i * 34
    if (sel) out.push(`<rect x="6" y="${y}" width="${w - 12}" height="30" rx="7" fill="${orange.s}"/>`)
    out.push(icon(ic, 15, y + 6, 18, sel ? "#ffffff" : T[color][0]))
    out.push(`<text x="42" y="${y + 20}" font-family="${MONO}" font-size="12.5" fill="${sel ? "#ffffff" : T.text}">${name}</text>`)
    out.push(`<text x="${w - 14}" y="${y + 20}" text-anchor="end" font-family="${MONO}" font-size="11" fill="${sel ? "#ffffff" : T.muted}">${size}</text>`)
  })
  return out.join("")
}

function wheelFace(w, h) {
  const orange = hue("orange")
  const cx = w / 2
  const cy = h / 2
  return [
    `<rect width="${w}" height="${h}" fill="${T.card}"/>`,
    wheel({ cx, cy, r0: 34, r1: 86, labels: ["JPEG", "PNG", "WEBP", "HEIC", "PDF", "TIFF"], accent: orange.s, fontSize: 11, active: 1, round: 7, gap: 3 }),
    `<circle cx="${cx}" cy="${cy}" r="28" fill="${T.ink}" stroke="${orange.s}" stroke-opacity=".4"/>`,
    `<text x="${cx}" y="${cy + 10}" text-anchor="middle" font-family="${SANS}" font-size="28" fill="${orange.s}">⇧</text>`,
  ].join("")
}

function savedFace(w, h) {
  const lime = hue("lime")
  const orange = hue("orange")
  const out = [`<rect width="${w}" height="${h}" fill="${T.card}"/>`, windowChrome(w, "Downloads")]
  out.push(icon("image", 15, 46, 18, lime.s))
  out.push(`<text x="42" y="60" font-family="${MONO}" font-size="12.5" fill="${T.text}">photo.heic</text><text x="${w - 14}" y="60" text-anchor="end" font-family="${MONO}" font-size="11" fill="${T.muted}">4.2 MB</text>`)
  // The new file lands once the bar is full.
  out.push(`<g opacity="0"><animate attributeName="opacity" values="0;0;1;1;0" keyTimes="0;.55;.62;.94;1" dur="6s" repeatCount="indefinite"/>`)
  out.push(`<rect x="6" y="74" width="${w - 12}" height="30" rx="7" fill="${lime.s}" fill-opacity=".14" stroke="${lime.s}" stroke-opacity=".5"/>`)
  out.push(icon("image", 15, 80, 18, lime.s))
  out.push(`<text x="42" y="94" font-family="${MONO}" font-size="12.5" fill="${T.text}">photo.png</text><text x="${w - 14}" y="94" text-anchor="end" font-family="${MONO}" font-size="11" fill="${lime.s}">✓ 2.1 MB</text>`)
  out.push(`</g>`)
  out.push(`<text x="14" y="${h - 38}" font-family="${MONO}" font-size="11" fill="${T.muted}">Converting to PNG</text>`)
  out.push(`<rect x="14" y="${h - 28}" width="${w - 28}" height="7" rx="3.5" fill="${T.line}" opacity=".25"/>`)
  out.push(`<rect x="14" y="${h - 28}" width="0" height="7" rx="3.5" fill="${orange.s}"><animate attributeName="width" values="0;0;${w - 28};${w - 28};0" keyTimes="0;.3;.55;.94;1" dur="6s" repeatCount="indefinite"/></rect>`)
  return out.join("")
}

function workflow() {
  const W = 1280
  const H = 470
  const orange = hue("orange")
  const box = { x: 0, y: 0, z: 30, w: 250, h: 180, t: 12 }
  const at = (center) => [r(center - ((box.w - box.h) / 2) * C), 110]
  const o1 = at(214)
  const o2 = at(640)
  const o3 = at(1066)
  const beam = (a, b, color, delay) => {
    const mx = (a[0] + b[0]) / 2
    const my = Math.min(a[1], b[1]) - 80
    const path = `M ${a[0]} ${a[1]} Q ${mx} ${my} ${b[0]} ${b[1]}`
    return `<path d="${path}" fill="none" stroke="${T.line}" stroke-opacity=".5" stroke-width="2" stroke-dasharray="3 7" class="run"/><circle r="5" fill="${color}" filter="url(#glow)"><animateMotion dur="2.2s" begin="${delay}s" repeatCount="indefinite" path="${path}"/></circle>`
  }
  const right1 = P(o1, box.w, box.h * 0.3, box.z)
  const left2 = P(o2, box.w * 0.15, box.h, box.z)
  const right2 = P(o2, box.w, box.h * 0.3, box.z)
  const left3 = P(o3, box.w * 0.15, box.h, box.z)
  const pointer = P(o1, box.w * 0.62, 62, box.z)
  const step = (x, n, title, sub, color) =>
    `<g font-family="${MONO}" text-anchor="middle"><text x="${x}" y="390" font-size="12" letter-spacing="3" fill="${color}">STEP ${n}</text><text x="${x}" y="418" font-family="${SANS}" font-size="21" font-weight="700" fill="${T.text}">${esc(title)}</text><text x="${x}" y="444" font-size="12.5" fill="${T.muted}">${esc(sub)}</text></g>`
  const body = `
    ${isoGrid(W, H, 34)}
    <ellipse cx="214" cy="230" rx="240" ry="150" fill="url(#glowLime)"/>
    <ellipse cx="640" cy="220" rx="240" ry="160" fill="url(#glowOrange)"/>
    <ellipse cx="1066" cy="230" rx="240" ry="150" fill="url(#glowSky)"/>
    ${particles(W, H, 12, 3)}
    ${tile(o1, box, finderFace, hue("lime"), { float: "float", ground: -10 })}
    ${tile(o2, box, wheelFace, hue("orange"), { float: "float d1", ground: -10 })}
    ${tile(o3, box, savedFace, hue("sky"), { float: "float d2", ground: -10 })}
    <g class="float">${cursor(pointer[0], pointer[1], 1.2)}</g>
    ${beam([right1[0] + 4, right1[1] - 12], [left2[0] - 2, left2[1] - 52], T.lime[0], 0)}
    ${beam([right2[0] + 4, right2[1] - 12], [left3[0] - 2, left3[1] - 52], orange.s, -1.1)}
    ${step(214, 1, "Select files in Finder", "one, or a whole batch", T.lime[0])}
    ${step(640, 2, "Drag, hold ⇧, drop on PNG", "⌘ opens tools · ⌃ file actions", orange.s)}
    ${step(1066, 3, "Get the result", "saved beside the original", T.sky[0])}`
  return svg(W, H, body, "Select files in Finder, drag with Shift held, drop on a format: the result is saved beside the original")
}

/* ---- 3. gestures: three modifier keys, three wheels -------------------- */

function gestures() {
  const W = 1280
  const H = 500
  const keys = [
    { glyph: "⇧", word: "SHIFT", title: "Convert", sub: "every format your files can become", color: "orange", labels: ["JPEG", "PNG", "WEBP", "HEIC", "PDF", "TIFF"] },
    { glyph: "⌘", word: "COMMAND", title: "Tools", sub: "crop · trim · compress… (or ⌥⇧)", color: "lime", labels: ["CROP", "RESIZE", "ROTATE", "EDIT", "PDF", "COMPRESS"] },
    { glyph: "⌃", word: "CONTROL", title: "File actions", sub: "reveal · copy · SHA-256", color: "grape", labels: ["REVEAL", "COPY", "PATHS", "DUPLICATE", "SHA-256"] },
  ]
  const parts = []
  keys.forEach((key, i) => {
    const c = hue(key.color)
    const colX = 34 + i * 410
    const o = [colX + 92, 150]
    const size = 100
    const kt = "0;.04;.09;.28;.34;1"
    const op = (lo, hi) => `<animate attributeName="opacity" values="${lo};${lo};${hi};${hi};${lo};${lo}" keyTimes="${kt}" dur="6s" begin="${i * 2}s" repeatCount="indefinite"/>`
    const glowId = `glow${key.color[0].toUpperCase()}${key.color.slice(1)}`
    parts.push(`<ellipse cx="${colX + 220}" cy="250" rx="200" ry="150" fill="url(#${glowId})"/>`)
    // the keycap, pressed in turn
    parts.push(`<g>${shadow(o, { x: 8, y: 14, w: size, h: size }, 0, "soft", 0.6)}</g>`)
    parts.push(`<g class="press k${i}">`)
    parts.push(slab(o, { x: 0, y: 0, z: 26, w: size, h: size, t: 22 }, { top: T.ink, right: c.lit, left: c.shade }))
    parts.push(`<g transform="${plane(o, 0, 0, 26)}">${keyFace(size, size, key.glyph, key.word, c.s)}</g>`)
    parts.push(`</g>`)
    // the wheel it opens, lit while the key is down
    const wx = colX + 306
    const wy = 196
    parts.push(`<g opacity=".42">${op(0.42, 1)}`)
    parts.push(`<circle cx="${wx}" cy="${wy}" r="102" fill="${T.ink}" fill-opacity=".6" stroke="${c.s}" stroke-opacity=".35" stroke-dasharray="2 5"/>`)
    parts.push(wheel({ cx: wx, cy: wy, r0: 38, r1: 96, labels: key.labels, accent: c.s, fontSize: key.labels.some((l) => l.length > 7) ? 9.6 : 10.5, step: 0.5, round: 7, gap: 3 }))
    parts.push(`<circle cx="${wx}" cy="${wy}" r="31" fill="${T.ink}" stroke="${c.s}" stroke-opacity=".45"/>`)
    parts.push(`<text x="${wx}" y="${wy + 10}" text-anchor="middle" font-family="${SANS}" font-size="27" fill="${c.s}">${key.glyph}</text>`)
    parts.push(`</g>`)
    // words
    parts.push(`<g font-family="${SANS}"><text x="${colX + 40}" y="394" font-family="${MONO}" font-size="12.5" letter-spacing="3" fill="${c.s}">HOLD ${key.word}</text>`)
    parts.push(`<text x="${colX + 38}" y="428" font-size="28" font-weight="800" fill="${T.text}">${key.title}</text>`)
    parts.push(`<text x="${colX + 40}" y="456" font-family="${MONO}" font-size="13" fill="${T.muted}">${esc(key.sub)}</text></g>`)
    parts.push(`<rect x="${colX + 40}" y="472" width="130" height="3" rx="1.5" fill="${c.s}" opacity=".2">${op(0.2, 1)}</rect>`)
  })
  const body = `
    ${isoGrid(W, H, 34)}
    ${particles(W, H, 10, 5)}
    <text x="640" y="44" text-anchor="middle" font-family="${MONO}" font-size="13" letter-spacing="3" fill="${T.muted}">WHILE DRAGGING FILES IN FINDER</text>
    ${parts.join("\n    ")}`
  return svg(W, H, body, "Hold Shift to convert, Command for tools, Control for file actions, while dragging files")
}

/* ---- 4. formats: the route families as blocks -------------------------- */

const FAMILIES = [
  { name: "Images", routes: 59, color: "lime", icon: "image", list: "JPEG PNG WEBP HEIC TIFF AVIF BMP SVG", to: "→ 8 image formats, PDF, DOCX" },
  { name: "Audio", routes: 56, color: "berry", icon: "audio", list: "MP3 M4A WAV FLAC OGG OPUS AIFF WMA", to: "→ any of the 8" },
  { name: "Video", routes: 48, color: "grape", icon: "video", list: "MP4 MOV MKV WEBM AVI WMV GIF", to: "→ video, GIF, MP3" },
  { name: "Documents", routes: 9, color: "lemon", icon: "doc", list: "PDF TXT", to: "→ DOCX, JPEG, PNG, TXT, PDF, SRT, VTT" },
  { name: "Subtitles", routes: 4, color: "sky", icon: "subtitle", list: "SRT VTT", to: "→ SRT, VTT, TXT" },
  { name: "Archives", routes: 0, color: "stone", icon: "archive", list: "ZIP TAR GZ RAR", to: "paused until extraction is sandboxed" },
]

function formats() {
  const W = 1280
  const H = 620
  const cubes = FAMILIES.map((fam, i) => {
    const c = hue(fam.color)
    const col = i % 3
    const row = Math.floor(i / 3)
    const o = [110 + col * 395, 170 + row * 250]
    const size = 92
    const height = 18 + fam.routes * 1.35
    const off = fam.routes === 0
    const top = (w, h) =>
      [
        `<rect width="${w}" height="${h}" fill="${c.s}" fill-opacity="${off ? 0.05 : 0.12}"/>`,
        `<rect x="7" y="7" width="${w - 14}" height="${h - 14}" fill="none" stroke="${c.s}" stroke-opacity=".7" stroke-dasharray="2 4"/>`,
        icon(fam.icon, w / 2 - 20, h / 2 - 20, 40, c.s, 2.2),
      ].join("")
    return `
      <g class="breathe d${i % 4}">${shadow(o, { x: 8, y: 14, w: size, h: size }, 0, "soft", 0.6)}</g>
      <g class="float d${i % 4}">
        ${slab(o, { x: 0, y: 0, z: height, w: size, h: size, t: height }, { top: T.ink, right: c.lit, left: c.shade })}
        <g transform="${plane(o, 0, 0, height)}">${top(size, size)}</g>
      </g>
      <g font-family="${MONO}">
        <text x="${o[0] + 104}" y="${o[1] + 20}" font-size="23" fill="${T.text}" font-family="${SANS}" font-weight="800">${fam.name}</text>
        <text x="${o[0] + 104}" y="${o[1] + 46}" font-size="13" fill="${c.s}">${off ? "0 routes · paused" : `${fam.routes} routes`}</text>
        <text x="${o[0] + 104}" y="${o[1] + 70}" font-size="11" fill="${T.text}" opacity=".8">${fam.list}</text>
        <text x="${o[0] + 104}" y="${o[1] + 90}" font-size="10.5" fill="${T.muted}">${esc(fam.to)}</text>
      </g>`
  }).join("")
  const body = `
    ${isoGrid(W, H, 34)}
    <ellipse cx="640" cy="310" rx="580" ry="290" fill="url(#glowOrange)" opacity=".55"/>
    ${particles(W, H, 18, 5)}
    ${cubes}
    <text x="640" y="${H - 22}" text-anchor="middle" font-family="${MONO}" font-size="13" fill="${T.muted}">block height = number of conversion routes · <tspan fill="${T.orange[0]}">176 in total</tspan></text>`
  return svg(W, H, body, "176 conversion routes across images, audio, video, documents and subtitles")
}

/* ---- 5. tools: every tool, by family ----------------------------------- */

const TOOLBOX = {
  images: { name: "Images", color: "lime", icon: "image", tools: [["edit", "Edit photo"], ["frame", "Add a background"], ["cutout", "Remove background"], ["crop", "Crop"], ["redact", "Redact"], ["resize", "Resize"], ["rotate", "Rotate & flip"], ["doc", "Create a PDF"], ["collage", "Collage"]] },
  video: { name: "Video", color: "grape", icon: "video", tools: [["trim", "Trim"], ["crop", "Crop"], ["speed", "Change speed"], ["link", "Join"], ["frames", "Save frames"], ["split", "Split"], ["redact", "Redact"]] },
  audio: { name: "Audio", color: "berry", icon: "audio", tools: [["wave", "Normalize volume"], ["bars", "Visualizer"], ["trim", "Trim"], ["phones", "Channels"], ["bleep", "Bleep"]] },
  pdf: { name: "PDF", color: "lemon", icon: "doc", tools: [["merge", "Merge"], ["stack", "Organize pages"], ["splitdoc", "Split"]] },
  any: { name: "Any file", color: "orange", icon: "layers", tools: [["compress", "Compress"], ["tag", "Edit metadata"]] },
  actions: { name: "File actions", color: "mint", icon: "folder", tools: [["folder", "Reveal in Finder"], ["copy", "Copy files"], ["link", "Copy paths"], ["dup", "Duplicate"], ["hash", "SHA-256 checksum"]], note: "hold ⌃" },
}

function tools() {
  const W = 1280
  const H = 600
  const columns = [["images"], ["video"], ["audio", "pdf"], ["any", "actions"]]
  const colW = 282
  const gap = 24
  const x0 = (W - (colW * columns.length + gap * (columns.length - 1))) / 2
  const chipH = 38
  const pitch = 46
  const parts = []
  const dur = 8
  let n = 0
  columns.forEach((keys, ci) => {
    const x = x0 + ci * (colW + gap)
    let y = 44
    for (const key of keys) {
      const fam = TOOLBOX[key]
      const c = hue(fam.color)
      parts.push(icon(fam.icon, x + 2, y + 4, 20, c.s, 1.8))
      parts.push(`<text x="${x + 32}" y="${y + 20}" font-family="${SANS}" font-size="18" font-weight="800" fill="${T.text}">${fam.name}</text>`)
      parts.push(`<text x="${x + colW - 4}" y="${y + 20}" text-anchor="end" font-family="${MONO}" font-size="12.5" fill="${c.s}">${fam.note ? `${fam.note} · ` : ""}${fam.tools.length}</text>`)
      parts.push(`<line x1="${x}" y1="${y + 32}" x2="${x + colW}" y2="${y + 32}" stroke="${c.s}" stroke-opacity=".5" stroke-dasharray="2 4"/>`)
      y += 44
      fam.tools.forEach(([ic, label]) => {
        const begin = r((n * 0.27) % dur)
        n += 1
        parts.push(`<rect x="${x}" y="${y}" width="${colW}" height="${chipH}" rx="10" fill="${c.s}" fill-opacity=".07" stroke="${c.s}" stroke-opacity=".28"/>`)
        parts.push(`<rect x="${x}" y="${y}" width="${colW}" height="${chipH}" rx="10" fill="${c.s}" fill-opacity=".2" stroke="${c.s}" stroke-opacity=".9" opacity="0"><animate attributeName="opacity" values="0;1;0;0" keyTimes="0;.05;.18;1" dur="${dur}s" begin="${begin}s" repeatCount="indefinite"/></rect>`)
        parts.push(icon(ic, x + 13, y + 10, 18, c.s, 1.6))
        parts.push(`<text x="${x + 44}" y="${y + 24.5}" font-family="${SANS}" font-size="15" font-weight="500" fill="${T.text}">${esc(label)}</text>`)
        y += pitch
      })
      y += 26
    }
  })
  const body = `
    ${isoGrid(W, H, 34)}
    <ellipse cx="320" cy="300" rx="320" ry="260" fill="url(#glowLime)" opacity=".7"/>
    <ellipse cx="960" cy="300" rx="320" ry="260" fill="url(#glowGrape)" opacity=".6"/>
    ${parts.join("\n    ")}
    <text x="640" y="${H - 20}" text-anchor="middle" font-family="${MONO}" font-size="13" fill="${T.muted}">hold ⌘ while dragging · the wheel only offers the tools that fit the files you hold</text>`
  return svg(W, H, body, "26 tools and 5 file actions: images, video, audio, PDF and any file")
}

/* ---- 6. notch: progress that grows out of the hardware notch ----------- */

function notch() {
  const W = 1280
  const H = 430
  const orange = hue("orange")
  const lime = hue("lime")
  const dur = 9
  const sx0 = 150
  const sx1 = 1130
  const sy = 58
  const cx = 640
  const rest = { w: 200, h: 32 }
  const open = { w: 600, h: 128 }
  const times = [0, 0.9, 1.5, 7.5, 8.1, 9]
  const kt = times.map((t) => r(t / dur)).join(";")
  const splines = [LIN, EASE, LIN, EASE, LIN].join(";")
  const seq = (a, b) => [a, a, b, b, a, a].join(";")
  const anim = (attr, a, b) => `<animate attributeName="${attr}" values="${seq(a, b)}" keyTimes="${kt}" calcMode="spline" keySplines="${splines}" dur="${dur}s" repeatCount="indefinite"/>`
  const show = (t0, t1, t2, t3) => `<animate attributeName="opacity" values="0;0;1;1;0;0" keyTimes="0;${r(t0 / dur)};${r(t1 / dur)};${r(t2 / dur)};${r(t3 / dur)};1" dur="${dur}s" repeatCount="indefinite"/>`
  const px = cx - open.w / 2
  const wall = T.name === "light"
  const body = `
    <defs>
      <linearGradient id="wall-${T.name}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${T.paper[0]}"/><stop offset="1" stop-color="${T.paper[1]}"/></linearGradient>
      <linearGradient id="screenFade-${T.name}" x1="0" y1="0" x2="0" y2="1"><stop offset=".55" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
      <mask id="screenMask-${T.name}" maskUnits="userSpaceOnUse" x="0" y="0" width="${W}" height="${H}"><rect width="${W}" height="${H - 70}" fill="url(#screenFade-${T.name})"/></mask>
      <radialGradient id="citrus-${T.name}" cx=".35" cy=".3" r=".8"><stop offset="0" stop-color="#ffc85c"/><stop offset="1" stop-color="#ee672c"/></radialGradient>
    </defs>
    <g mask="url(#screenMask-${T.name})">
      <!-- the lid and the screen -->
      <rect x="${sx0 - 16}" y="${sy - 16}" width="${sx1 - sx0 + 32}" height="${H}" rx="26" fill="#0b0b0c" stroke="${wall ? "#c9c9c2" : "#3a3d44"}"/>
      <rect x="${sx0}" y="${sy}" width="${sx1 - sx0}" height="${H}" rx="10" fill="url(#wall-${T.name})"/>
      <ellipse cx="380" cy="250" rx="260" ry="130" fill="url(#glowOrange)"/>
      <ellipse cx="900" cy="270" rx="260" ry="130" fill="url(#glowLime)"/>
      <!-- menu bar -->
      <rect x="${sx0}" y="${sy}" width="${sx1 - sx0}" height="28" fill="${wall ? "#ffffff" : "#000000"}" fill-opacity="${wall ? 0.55 : 0.35}"/>
      <g font-family="${SANS}" font-size="12.5" fill="${T.text}">
        <circle cx="${sx0 + 22}" cy="${sy + 14}" r="5" fill="${T.text}" opacity=".8"/>
        <text x="${sx0 + 40}" y="${sy + 18.5}" font-weight="700">Finder</text>
        <text x="${sx0 + 96}" y="${sy + 18.5}">File</text>
        <text x="${sx0 + 132}" y="${sy + 18.5}">Edit</text>
        <text x="${sx0 + 168}" y="${sy + 18.5}">View</text>
        <text x="${sx0 + 210}" y="${sy + 18.5}">Go</text>
        <text x="${sx1 - 20}" y="${sy + 18.5}" text-anchor="end">Mon 9:41</text>
        <rect x="${sx1 - 120}" y="${sy + 9}" width="20" height="10" rx="2.5" fill="none" stroke="${T.text}" opacity=".7"/>
        <rect x="${sx1 - 118}" y="${sy + 11}" width="13" height="6" rx="1" fill="${T.text}" opacity=".7"/>
      </g>
      <g transform="translate(${sx1 - 160} ${sy + 4}) scale(.2)">${mark(50, 50, 100, { color: orange.s })}</g>
      <!-- a file on the desktop -->
      <g transform="translate(${sx1 - 150} ${sy + 90})">
        <rect width="64" height="48" rx="6" fill="${hue("grape").shade}"/>
        <path d="M27 16L40 24L27 32Z" fill="#fff"/>
        <text x="32" y="66" text-anchor="middle" font-family="${SANS}" font-size="11" fill="${T.text}">geese.mov</text>
      </g>
      <g transform="translate(${sx0 + 80} ${sy + 90})">
        <rect width="54" height="66" rx="5" fill="${T.card}" stroke="${T.line}" stroke-opacity=".6"/>
        <rect x="9" y="12" width="20" height="8" rx="2" fill="${hue("lemon").s}"/>
        <rect x="9" y="28" width="34" height="3" rx="1.5" fill="${T.line}" opacity=".6"/><rect x="9" y="36" width="28" height="3" rx="1.5" fill="${T.line}" opacity=".6"/><rect x="9" y="44" width="32" height="3" rx="1.5" fill="${T.line}" opacity=".6"/>
        <text x="27" y="84" text-anchor="middle" font-family="${SANS}" font-size="11" fill="${T.text}">report.pdf</text>
      </g>
    </g>

    <!-- the notch grows into a panel; the clip keeps its top flush with the lid -->
    <clipPath id="lid-${T.name}"><rect x="0" y="${sy - 15}" width="${W}" height="${H}"/></clipPath>
    <g clip-path="url(#lid-${T.name})">
      <rect x="${cx - rest.w / 2}" y="${sy - 40}" width="${rest.w}" height="${rest.h + 40}" rx="30" fill="#000000">
        ${anim("x", cx - rest.w / 2, cx - open.w / 2)}${anim("width", rest.w, open.w)}${anim("height", rest.h + 40, open.h + 40)}
      </rect>
    </g>
    <g opacity="0">${show(1.3, 1.7, 7.3, 7.7)}
      <g transform="translate(${px + 58} ${sy + 62})">
        <circle r="27" fill="url(#citrus-${T.name})"/>
        <path d="M2 -26C4 -36 14 -38 20 -35C18 -28 10 -25 2 -26Z" fill="#7eaa62"/>
        <g fill="#422310">
          <ellipse cx="-9" cy="-4" rx="3.2" ry="4.6"><animate attributeName="ry" values="4.6;4.6;.6;4.6;4.6" keyTimes="0;.46;.5;.54;1" dur="3s" repeatCount="indefinite"/></ellipse>
          <ellipse cx="9" cy="-4" rx="3.2" ry="4.6"><animate attributeName="ry" values="4.6;4.6;.6;4.6;4.6" keyTimes="0;.46;.5;.54;1" dur="3s" repeatCount="indefinite"/></ellipse>
        </g>
        <path d="M-6 8Q0 14 6 8" fill="none" stroke="#422310" stroke-width="2.4" stroke-linecap="round"/>
      </g>
      <!-- working -->
      <g opacity="0">${show(1.4, 1.7, 5.7, 6)}
        <text x="${px + 106}" y="${sy + 52}" font-family="${SANS}" font-size="18" font-weight="600" fill="#ffffff">Compressing</text>
        <text x="${px + 106}" y="${sy + 74}" font-family="${MONO}" font-size="12" fill="#a1a1a6">geese.mov · 64.2 MB</text>
        <rect x="${px + 106}" y="${sy + 88}" width="440" height="7" rx="3.5" fill="#ffffff" fill-opacity=".14"/>
        <rect x="${px + 106}" y="${sy + 88}" width="0" height="7" rx="3.5" fill="${T.orange[0]}">
          <animate attributeName="width" values="0;0;440;440;0" keyTimes="0;${r(1.7 / dur)};${r(5.5 / dur)};${r(5.9 / dur)};1" dur="${dur}s" repeatCount="indefinite"/>
        </rect>
      </g>
      <!-- done -->
      <g opacity="0">${show(5.8, 6.1, 7.3, 7.6)}
        <text x="${px + 106}" y="${sy + 52}" font-family="${SANS}" font-size="18" font-weight="600" fill="#ffffff">Saved <tspan fill="${THEMES.dark.lime[0]}">✓</tspan></text>
        <text x="${px + 106}" y="${sy + 74}" font-family="${MONO}" font-size="12" fill="#a1a1a6">geese.mov · 64.2 MB → <tspan fill="#ffffff">18.9 MB</tspan></text>
        <rect x="${px + 106}" y="${sy + 84}" width="66" height="26" rx="13" fill="#ffffff" fill-opacity=".16"/>
        <text x="${px + 139}" y="${sy + 101}" text-anchor="middle" font-family="${SANS}" font-size="12.5" font-weight="600" fill="#ffffff">Open</text>
        <rect x="${px + 180}" y="${sy + 84}" width="126" height="26" rx="13" fill="#ffffff" fill-opacity=".16"/>
        <text x="${px + 243}" y="${sy + 101}" text-anchor="middle" font-family="${SANS}" font-size="12.5" font-weight="600" fill="#ffffff">Show in Finder</text>
      </g>
    </g>

    <g font-family="${MONO}" font-size="12.5" fill="${T.muted}">
      ${[
        ["pure black or glass, your choice", orange.s, 230],
        ["Open · Show in Finder when done", lime.s, 640],
        ["Reduce Motion & Transparency respected", T.grape[0], 1050],
      ]
        .map(([label, color, x]) => `<circle cx="${x - label.length * 3.9 - 12}" cy="${H - 31}" r="4" fill="${color}"/><text x="${x}" y="${H - 27}" text-anchor="middle">${esc(label)}</text>`)
        .join("")}
    </g>`
  return svg(W, H, body, "Progress grows out of the MacBook notch: a citrus companion, the file, a progress bar, then Open and Show in Finder")
}

/* ---- 7. roadmap: what this fork adds next ------------------------------ */

const ROADMAP = [
  {
    name: "Shipped",
    note: "0.1.8 + this fork",
    color: "lime",
    cards: [
      ["check", "176 routes, 26 tools", "convert, crop, trim, merge, redact…"],
      ["cutout", "Remove background", "new in this fork · transparent PNG"],
      ["check", "Batch & notch progress", "a failed file never stops the rest"],
    ],
  },
  {
    name: "Next in this fork",
    note: "in progress",
    color: "orange",
    cards: [
      ["compress", "Compression 2.0", "video · images · PDF · target size"],
      ["archive", "ZIP in one drop", "zip a selection, unzip safely"],
    ],
    live: true,
  },
  {
    name: "Later",
    note: "planned",
    color: "grape",
    cards: [
      ["ocr", "Text from images", "OCR with Apple Vision, copy or .txt"],
      ["watch", "Watch folders", "drop in a folder, get it converted"],
      ["wand", "Batch rename & watermark", "presets you can reuse"],
    ],
  },
]

function roadmap() {
  const W = 1280
  const H = 520
  const colW = 384
  const gap = 24
  const x0 = (W - (colW * 3 + gap * 2)) / 2
  const parts = []
  ROADMAP.forEach((col, ci) => {
    const c = hue(col.color)
    const x = x0 + ci * (colW + gap)
    parts.push(`<rect x="${x}" y="40" width="${colW}" height="${H - 80}" rx="18" fill="${c.s}" fill-opacity=".05" stroke="${c.s}" stroke-opacity=".35" stroke-dasharray="2 5"/>`)
    parts.push(`<circle cx="${x + 26}" cy="76" r="6" fill="${c.s}">${col.live ? `<animate attributeName="r" values="6;9;6" dur="1.6s" repeatCount="indefinite"/><animate attributeName="opacity" values="1;.4;1" dur="1.6s" repeatCount="indefinite"/>` : ""}</circle>`)
    parts.push(`<text x="${x + 42}" y="82" font-family="${SANS}" font-size="19" font-weight="800" fill="${T.text}">${col.name}</text>`)
    parts.push(`<text x="${x + colW - 20}" y="82" text-anchor="end" font-family="${MONO}" font-size="11" letter-spacing="1" fill="${c.s}">${col.note.toUpperCase()}</text>`)
    col.cards.forEach(([ic, title, sub], k) => {
      const y = 108 + k * 120
      parts.push(col.live ? `<g class="float d${k % 4}" style="animation-duration:${7 + k}s">` : `<g>`)
      parts.push(`<rect x="${x + 16}" y="${y}" width="${colW - 32}" height="104" rx="14" fill="${T.ink}" stroke="${c.s}" stroke-opacity="${col.live ? 0.55 : 0.3}"/>`)
      parts.push(`<rect x="${x + 32}" y="${y + 18}" width="40" height="40" rx="11" fill="${c.s}" fill-opacity=".12"/>`)
      parts.push(icon(ic, x + 40, y + 26, 24, c.s, 1.8))
      parts.push(`<text x="${x + 88}" y="${y + 38}" font-family="${SANS}" font-size="17" font-weight="700" fill="${T.text}">${esc(title)}</text>`)
      parts.push(`<text x="${x + 88}" y="${y + 60}" font-family="${MONO}" font-size="11.5" fill="${T.muted}">${esc(sub)}</text>`)
      if (col.live) {
        const w = colW - 120
        const done = [0.45, 0.3, 0.15][k]
        parts.push(`<rect x="${x + 88}" y="${y + 76}" width="${w}" height="6" rx="3" fill="${c.s}" fill-opacity=".15"/>`)
        parts.push(`<rect x="${x + 88}" y="${y + 76}" width="${r(w * done)}" height="6" rx="3" fill="${c.s}"><animate attributeName="width" values="${r(w * done * 0.6)};${r(w * done)};${r(w * done)};${r(w * done * 0.6)}" keyTimes="0;.4;.85;1" dur="5s" begin="${k * 0.4}s" repeatCount="indefinite"/></rect>`)
      } else if (col.name === "Shipped") {
        parts.push(`<text x="${x + 88}" y="${y + 86}" font-family="${MONO}" font-size="10.5" fill="${c.s}">✓ available</text>`)
      } else {
        parts.push(`<text x="${x + 88}" y="${y + 86}" font-family="${MONO}" font-size="10.5" fill="${T.muted}">○ not started</text>`)
      }
      parts.push(`</g>`)
    })
  })
  const body = `
    ${isoGrid(W, H, 34)}
    <ellipse cx="640" cy="260" rx="330" ry="230" fill="url(#glowOrange)"/>
    ${parts.join("\n    ")}`
  return svg(W, H, body, "Roadmap: shipped (176 routes, 26 tools, background removal), next in this fork (compression 2.0, ZIP), later")
}

/* ---- 8. divider: a dotted rule with a segment of zest running along it -- */

function divider() {
  const W = 1280
  const H = 28
  const o = T.orange[0]
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}" role="img" aria-label="divider">
  <style>.run { animation: run 2.4s linear infinite } @keyframes run { to { stroke-dashoffset: -14 } } @media (prefers-reduced-motion: reduce) { .run { animation: none } }</style>
  <line class="run" x1="30" y1="14" x2="${W - 30}" y2="14" stroke="${T.line}" stroke-opacity=".55" stroke-width="1.5" stroke-dasharray="2 5"/>
  <circle cx="16" cy="14" r="5" fill="none" stroke="${o}" stroke-width="1.6"/>
  <circle cx="${W - 16}" cy="14" r="5" fill="none" stroke="${o}" stroke-width="1.6"/>
  <circle cy="14" r="3" fill="${o}"><animate attributeName="cx" values="30;${W - 30}" dur="9s" repeatCount="indefinite"/><animate attributeName="opacity" values="0;1;1;0" keyTimes="0;.08;.92;1" dur="9s" repeatCount="indefinite"/></circle>
</svg>
`
}

/* ---- build ------------------------------------------------------------ */

for (const theme of ["light", "dark"]) {
  useTheme(theme)
  const files = { hero: hero(), workflow: workflow(), gestures: gestures(), formats: formats(), tools: tools(), notch: notch(), roadmap: roadmap(), divider: divider() }
  for (const [name, content] of Object.entries(files)) {
    writeFileSync(join(OUT, `${name}-${theme}.svg`), content)
    console.log(`docs/readme/${name}-${theme}.svg  ${(content.length / 1024).toFixed(1)} kB`)
  }
}

