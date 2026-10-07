import type { Occasion, ThemeID } from './types';

export type Motion = 'lift' | 'turn' | 'fade';

export interface ThemeMeta { id: ThemeID; name: string; paper: string; motion: Motion; premium: boolean }

export const Themes: Record<ThemeID, ThemeMeta> = {
  letterpress: { id: 'letterpress', name: 'Letterpress', paper: '#F4EFE6', motion: 'lift', premium: false },
  midnight_toast: { id: 'midnight_toast', name: 'Midnight Toast', paper: '#0F1B2D', motion: 'lift', premium: false },
  chalk: { id: 'chalk', name: 'Chalk', paper: '#2F4A3E', motion: 'turn', premium: false },
  gold_leaf: { id: 'gold_leaf', name: 'Gold Leaf', paper: '#F6F1E7', motion: 'lift', premium: true },
  darkroom: { id: 'darkroom', name: 'Darkroom', paper: '#0B0B0C', motion: 'fade', premium: true },
  field_day: { id: 'field_day', name: 'Field Day', paper: '#2E7D4F', motion: 'turn', premium: true },
};

export function applyTheme(id: ThemeID | string | null | undefined): void {
  const t = Themes[(id ?? 'letterpress') as ThemeID] ?? Themes.letterpress;
  document.documentElement.dataset.theme = t.id;
  document.documentElement.dataset.motion = t.motion;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', t.paper);
}

export interface OccasionMeta { title: string; prompts: string[] }

export const Occasions: Record<Occasion, OccasionMeta> = {
  retirement: {
    title: 'Retirement',
    prompts: ['What did they teach you?', "A moment you'll never forget", 'What the place will miss', 'Advice for the first Monday off'],
  },
  new_job: {
    title: 'New job',
    prompts: ['What the next team is lucky to get', "The thing you'll miss most", 'A project you survived together', 'One piece of advice'],
  },
  graduation: {
    title: 'Graduation',
    prompts: ['Proudest moment', "Advice for what's next", 'What you noticed about them', 'Something to remember on a hard day'],
  },
  teacher: {
    title: 'Thank a teacher',
    prompts: ['Something they said that stuck', 'A day that changed things', 'What my kid says at dinner', 'Thank you for...'],
  },
  season_end: {
    title: 'End of season',
    prompts: ['Best game', 'What you learned beyond the sport', "A practice you'll never forget", 'Thank you, coach'],
  },
  military: {
    title: 'Military sendoff',
    prompts: ['Best memory from the unit', 'Something you taught us', 'A story from the field', "What we'll miss", 'Final words before you move on'],
  },
  farewell: {
    title: 'Leaving a team',
    prompts: ["What you'll miss", 'A story only you two know', 'Something you never got to say', 'What the next place is getting'],
  },
};

export function occasionTitle(o: Occasion | string): string {
  return Occasions[o as Occasion]?.title ?? 'Sendoff';
}
