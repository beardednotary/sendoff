import { Limits, type LocalMedia, type MediaKind } from './types';
import { uuid } from './format';

// Picking and recording media in the browser, with the same caps as the iOS app.

export function pickFiles(accept: string, multiple: boolean, capture?: 'user' | 'environment'): Promise<File[]> {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = accept;
    input.multiple = multiple;
    if (capture) input.setAttribute('capture', capture);
    input.style.display = 'none';
    input.addEventListener('change', () => { resolve([...(input.files ?? [])]); input.remove(); });
    input.addEventListener('cancel', () => { resolve([]); input.remove(); });
    document.body.appendChild(input);
    input.click();
  });
}

export async function imageFromFile(file: File): Promise<LocalMedia> {
  if (file.size > Limits.photoBytes) throw new Error(`That photo is too large. Keep each under ${Math.round(Limits.photoBytes / 1024 / 1024)} MB.`);
  const previewUrl = URL.createObjectURL(file);
  const dims = await new Promise<{ w: number; h: number }>((resolve) => {
    const img = new Image();
    img.onload = () => resolve({ w: img.naturalWidth, h: img.naturalHeight });
    img.onerror = () => resolve({ w: 0, h: 0 });
    img.src = previewUrl;
  });
  return { id: uuid(), kind: 'photo', file, previewUrl, durationSeconds: null, width: dims.w || null, height: dims.h || null, mime: file.type || 'image/jpeg' };
}

export async function videoFromFile(file: File): Promise<LocalMedia> {
  if (file.size > Limits.videoBytes) throw new Error(`That video is too large. Keep it under ${Math.round(Limits.videoBytes / 1024 / 1024)} MB.`);
  const previewUrl = URL.createObjectURL(file);
  const meta = await probe('video', previewUrl);
  if (meta.duration != null && meta.duration > Limits.videoSeconds + 1) {
    URL.revokeObjectURL(previewUrl);
    throw new Error(`Videos can be up to ${Limits.videoSeconds} seconds. That one is ${Math.round(meta.duration)}.`);
  }
  return { id: uuid(), kind: 'video', file, previewUrl, durationSeconds: meta.duration, width: meta.width, height: meta.height, mime: file.type || 'video/mp4' };
}

function probe(kind: 'video' | 'audio', url: string): Promise<{ duration: number | null; width: number | null; height: number | null }> {
  return new Promise((resolve) => {
    const el = document.createElement(kind);
    el.preload = 'metadata';
    const done = () => {
      const d = Number.isFinite(el.duration) ? el.duration : null;
      resolve({ duration: d, width: kind === 'video' ? (el as HTMLVideoElement).videoWidth || null : null, height: kind === 'video' ? (el as HTMLVideoElement).videoHeight || null : null });
    };
    el.onloadedmetadata = done;
    el.onerror = () => resolve({ duration: null, width: null, height: null });
    el.src = url;
  });
}

export function canRecord(): boolean {
  return typeof MediaRecorder !== 'undefined' && !!navigator.mediaDevices?.getUserMedia;
}

export class VoiceRecorder {
  private recorder: MediaRecorder | null = null;
  private chunks: BlobPart[] = [];
  private stream: MediaStream | null = null;
  private startedAt = 0;
  private timer: number | undefined;
  private analyser: AnalyserNode | null = null;
  private ctx: AudioContext | null = null;
  onTick: (elapsed: number, level: number) => void = () => {};

  get mime(): string {
    for (const m of ['audio/mp4', 'audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus']) {
      if (MediaRecorder.isTypeSupported(m)) return m;
    }
    return '';
  }

  async start(): Promise<void> {
    this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    this.chunks = [];
    const mime = this.mime;
    this.recorder = new MediaRecorder(this.stream, mime ? { mimeType: mime } : undefined);
    this.recorder.ondataavailable = (e) => { if (e.data.size) this.chunks.push(e.data); };
    this.recorder.start(250);
    this.startedAt = performance.now();
    try {
      this.ctx = new AudioContext();
      const src = this.ctx.createMediaStreamSource(this.stream);
      this.analyser = this.ctx.createAnalyser();
      this.analyser.fftSize = 256;
      src.connect(this.analyser);
    } catch { this.analyser = null; }
    const data = new Uint8Array(128);
    const tick = () => {
      const elapsed = (performance.now() - this.startedAt) / 1000;
      let level = 0;
      if (this.analyser) {
        this.analyser.getByteTimeDomainData(data);
        let sum = 0;
        for (const v of data) { const x = (v - 128) / 128; sum += x * x; }
        level = Math.min(1, Math.sqrt(sum / data.length) * 3);
      }
      this.onTick(elapsed, level);
      if (elapsed >= Limits.voiceSeconds) void this.stop();
    };
    this.timer = window.setInterval(tick, 100);
  }

  stop(): Promise<LocalMedia> {
    return new Promise((resolve, reject) => {
      const rec = this.recorder;
      if (!rec) return reject(new Error('Not recording'));
      window.clearInterval(this.timer);
      const elapsed = (performance.now() - this.startedAt) / 1000;
      rec.onstop = () => {
        const type = rec.mimeType || this.mime || 'audio/webm';
        const file = new Blob(this.chunks, { type });
        this.cleanup();
        resolve({ id: uuid(), kind: 'voice', file, previewUrl: URL.createObjectURL(file), durationSeconds: Math.round(elapsed * 100) / 100, width: null, height: null, mime: type });
      };
      rec.stop();
    });
  }

  cancel(): void {
    window.clearInterval(this.timer);
    try { this.recorder?.stop(); } catch { /* already stopped */ }
    this.cleanup();
  }

  private cleanup(): void {
    this.stream?.getTracks().forEach((t) => t.stop());
    this.stream = null;
    this.recorder = null;
    void this.ctx?.close();
    this.ctx = null;
    this.analyser = null;
  }
}

export function kindLabel(kind: MediaKind): string {
  return kind === 'photo' ? 'Photo' : kind === 'voice' ? 'Voice note' : 'Video';
}
