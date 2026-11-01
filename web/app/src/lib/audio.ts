// Music bed for the reveal plus a shared player so a voice note or video ducks the music to 20%
// and it recovers over 1.5s (docs/DESIGN.md, Sound).

const DUCK = 0.2;
const FULL = 0.55;

export class MusicBed {
  private el: HTMLAudioElement | null = null;
  private target = FULL;
  private fade: number | undefined;
  enabled = true;
  onChange: (playing: boolean) => void = () => {};

  load(url: string | null): void {
    this.el?.pause();
    this.el = null;
    if (!url) return;
    const a = new Audio(url);
    a.loop = true;
    a.preload = 'auto';
    a.volume = 0;
    this.el = a;
  }

  get available(): boolean { return this.el != null; }
  get playing(): boolean { return !!this.el && !this.el.paused; }

  async play(): Promise<void> {
    if (!this.el || !this.enabled) return;
    try {
      await this.el.play();
      this.rampTo(this.target, 2000);
      this.onChange(true);
    } catch { /* autoplay refused; the user can tap the music button */ }
  }

  pause(): void {
    if (!this.el) return;
    this.rampTo(0, 600, () => this.el?.pause());
    this.onChange(false);
  }

  toggle(): void {
    this.enabled = !this.enabled;
    if (this.enabled) void this.play(); else this.pause();
  }

  duck(): void { this.target = DUCK; if (this.playing) this.rampTo(DUCK, 400); }
  recover(): void { this.target = FULL; if (this.playing) this.rampTo(FULL, 1500); }

  private rampTo(v: number, ms: number, done?: () => void): void {
    const el = this.el;
    if (!el) return;
    window.clearInterval(this.fade);
    const from = el.volume;
    const start = performance.now();
    this.fade = window.setInterval(() => {
      const t = Math.min(1, (performance.now() - start) / ms);
      el.volume = from + (v - from) * t;
      if (t >= 1) { window.clearInterval(this.fade); done?.(); }
    }, 40);
  }

  destroy(): void {
    window.clearInterval(this.fade);
    this.el?.pause();
    this.el = null;
  }
}

/** Only one voice note or video plays at a time; starting one stops the others. */
export class Foreground {
  private current: HTMLMediaElement | null = null;
  constructor(private bed: MusicBed) {}

  attach(el: HTMLMediaElement): void {
    el.addEventListener('play', () => {
      if (this.current && this.current !== el) this.current.pause();
      this.current = el;
      this.bed.duck();
    });
    const release = () => { if (this.current === el) { this.current = null; this.bed.recover(); } };
    el.addEventListener('pause', release);
    el.addEventListener('ended', release);
  }

  stopAll(): void {
    this.current?.pause();
    this.current = null;
    this.bed.recover();
  }
}
