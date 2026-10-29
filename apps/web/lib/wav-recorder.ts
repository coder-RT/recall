"use client";

/**
 * Microphone → mono 16-bit WAV at 24 kHz, for Muse Voice Transcribe (the rate its realtime docs
 * use). Records at the device rate and resamples here, because Firefox can't mix sample rates.
 */

const RATE = 24_000;
const MAX_SECONDS = 15;

export interface Recording {
  /** Stop and return the WAV. */
  stop: () => Promise<Blob>;
  /** Stop and throw the audio away. */
  cancel: () => void;
}

// copies each block of microphone samples to the main thread
const TAP = `class Tap extends AudioWorkletProcessor {
  process(inputs) { const ch = inputs[0][0]; if (ch) this.port.postMessage(ch.slice(0)); return true; }
}
registerProcessor("tap", Tap);`;

export async function startRecording(): Promise<Recording> {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true } });
  const ctx = new AudioContext();
  const url = URL.createObjectURL(new Blob([TAP], { type: "text/javascript" }));
  await ctx.audioWorklet.addModule(url);
  URL.revokeObjectURL(url);

  const source = ctx.createMediaStreamSource(stream);
  const tap = new AudioWorkletNode(ctx, "tap");
  const mute = ctx.createGain();
  mute.gain.value = 0; // keeps the graph running without playing the mic back
  source.connect(tap).connect(mute).connect(ctx.destination);

  const chunks: Float32Array[] = [];
  let length = 0;
  const limit = ctx.sampleRate * MAX_SECONDS;
  tap.port.onmessage = (e: MessageEvent<Float32Array>) => {
    if (length >= limit) return;
    chunks.push(e.data);
    length += e.data.length;
  };

  const release = () => {
    source.disconnect();
    tap.disconnect();
    stream.getTracks().forEach((t) => t.stop());
    void ctx.close();
  };

  return {
    stop: async () => {
      release();
      const samples = new Float32Array(length);
      let offset = 0;
      for (const c of chunks) {
        samples.set(c, offset);
        offset += c.length;
      }
      return encodeWav(resample(samples, ctx.sampleRate, RATE), RATE);
    },
    cancel: release,
  };
}

/** Linear-interpolation resample; fine for speech. */
function resample(input: Float32Array, from: number, to: number) {
  if (from === to) return input;
  const out = new Float32Array(Math.round((input.length * to) / from));
  const step = from / to;
  for (let i = 0; i < out.length; i++) {
    const pos = i * step;
    const j = Math.floor(pos);
    const t = pos - j;
    out[i] = (input[j] ?? 0) * (1 - t) + (input[j + 1] ?? input[j] ?? 0) * t;
  }
  return out;
}

/** 16-bit PCM mono WAV with the standard 44-byte header. */
function encodeWav(samples: Float32Array, rate: number) {
  const buffer = new ArrayBuffer(44 + samples.length * 2);
  const view = new DataView(buffer);
  const text = (at: number, s: string) => [...s].forEach((ch, i) => view.setUint8(at + i, ch.charCodeAt(0)));
  text(0, "RIFF");
  view.setUint32(4, 36 + samples.length * 2, true);
  text(8, "WAVE");
  text(12, "fmt ");
  view.setUint32(16, 16, true); // fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, rate, true);
  view.setUint32(28, rate * 2, true); // bytes per second
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits per sample
  text(36, "data");
  view.setUint32(40, samples.length * 2, true);
  samples.forEach((v, i) => {
    const s = Math.max(-1, Math.min(1, v));
    view.setInt16(44 + i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true);
  });
  return new Blob([buffer], { type: "audio/wav" });
}
