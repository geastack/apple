#!/usr/bin/env node
// Measures a capture produced by GEA_AUDIO_CAPTURE_RAW (see apple_audio.mm):
// raw interleaved float32 stereo at 48 kHz, written by the audio backend while a
// real app runs. Reports level, note onsets and the measured fundamental of each
// note, so "the app really made sound" is a measurement rather than a claim.
//
//   node analyze-audio-capture.mjs <capture.f32> [--rate 48000] [--notes 20]

import { readFileSync } from 'node:fs'

const args = process.argv.slice(2)
const path = args.find((a) => !a.startsWith('--'))
if (!path) {
  console.error('usage: analyze-audio-capture.mjs <capture.f32> [--rate 48000] [--notes 20]')
  process.exit(2)
}
const option = (name, fallback) => {
  const index = args.indexOf(`--${name}`)
  return index >= 0 && args[index + 1] ? Number(args[index + 1]) : fallback
}
const rate = option('rate', 48000)
const maxNotes = option('notes', 20)

const bytes = readFileSync(path)
const samples = new Float32Array(bytes.buffer, bytes.byteOffset, Math.floor(bytes.length / 4))
const frames = Math.floor(samples.length / 2)
const left = new Float32Array(frames)
for (let frame = 0; frame < frames; frame++) left[frame] = samples[frame * 2]

const rms = (from, to) => {
  let sum = 0
  for (let i = from; i < to; i++) sum += left[i] * left[i]
  return Math.sqrt(sum / Math.max(1, to - from))
}
const peak = (from, to) => {
  let worst = 0
  for (let i = from; i < to; i++) worst = Math.max(worst, Math.abs(left[i]))
  return worst
}
// Fundamental by hysteretic zero crossings — exact enough for the synth's
// single-tone output.
const frequency = (from, to) => {
  const threshold = 0.15 * peak(from, to)
  if (threshold <= 0) return 0
  let sign = 0
  let crossings = 0
  let first = 0
  let last = 0
  for (let i = from; i < to; i++) {
    const value = left[i]
    let next = sign
    if (value > threshold) next = 1
    else if (value < -threshold) next = -1
    if (next !== sign && sign !== 0) {
      if (crossings === 0) first = i
      last = i
      crossings++
    }
    sign = next
  }
  if (crossings < 3 || last <= first) return 0
  return (crossings - 1) / (2 * ((last - first) / rate))
}

// Envelope-follow in 1 ms hops; a note is a run above the gate.
const hop = Math.max(1, Math.round(rate / 1000))
const hops = Math.floor(frames / hop)
const envelope = new Float64Array(hops)
for (let h = 0; h < hops; h++) envelope[h] = rms(h * hop, (h + 1) * hop)
const loudest = envelope.reduce((a, b) => Math.max(a, b), 0)
const gate = Math.max(1e-4, loudest * 0.1)

const notes = []
let start = -1
for (let h = 0; h < hops; h++) {
  const loud = envelope[h] > gate
  if (loud && start < 0) start = h
  if (!loud && start >= 0) {
    if (h - start >= 8) notes.push([start, h])
    start = -1
  }
}
if (start >= 0 && hops - start >= 8) notes.push([start, hops])

const soundingHops = envelope.reduce((count, value) => count + (value > gate ? 1 : 0), 0)

console.log(`file            ${path}`)
console.log(`frames          ${frames} stereo @ ${rate} Hz  (${(frames / rate).toFixed(3)} s)`)
console.log(`overall rms     ${rms(0, frames).toFixed(6)}`)
console.log(`peak            ${peak(0, frames).toFixed(6)}`)
console.log(`sounding        ${((100 * soundingHops) / hops).toFixed(1)}% of the capture`)
console.log(`silent          ${((100 * (hops - soundingHops)) / hops).toFixed(1)}% of the capture`)
console.log(`gated runs      ${notes.length} (a legato melody is one run, see the pitch track)`)
console.log('')

// Pitch track: a melody whose notes butt up against each other never dips below
// the gate, so segment by PITCH instead. 30 ms windows every 10 ms, merged into
// runs whose fundamental agrees within 3%.
const windowFrames = Math.round(0.03 * rate)
const stepFrames = Math.round(0.01 * rate)
const track = []
for (let from = 0; from + windowFrames <= frames; from += stepFrames) {
  track.push({ from, hz: frequency(from, from + windowFrames), rms: rms(from, from + windowFrames) })
}
const runs = []
for (const point of track) {
  if (point.hz <= 0 || point.rms <= gate) {
    runs.push(null)
    continue
  }
  const last = runs.length > 0 ? runs[runs.length - 1] : null
  if (last && Math.abs(point.hz - last.hz) / last.hz < 0.03) {
    last.to = point.from + windowFrames
    last.hz = (last.hz * last.count + point.hz) / (last.count + 1)
    last.count++
  } else {
    runs.push({ from: point.from, to: point.from + windowFrames, hz: point.hz, count: 1 })
  }
}
const melody = runs.filter((run) => run && run.to - run.from >= Math.round(0.05 * rate))
console.log(`pitch runs      ${melody.length}`)
console.log('')
console.log('  #   start(s)  dur(ms)      rms     freq(Hz)')
for (const [index, run] of melody.slice(0, maxNotes).entries()) {
  console.log(
    `  ${String(index + 1).padStart(2)}  ${(run.from / rate).toFixed(4)}  ` +
      `${String(Math.round((1000 * (run.to - run.from)) / rate)).padStart(6)}  ` +
      `${rms(run.from, run.to).toFixed(5)}  ${run.hz.toFixed(1).padStart(9)}`,
  )
}
if (melody.length > maxNotes) console.log(`  ... ${melody.length - maxNotes} more`)
