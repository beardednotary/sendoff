// Mirrors supabase/migrations and ios/Sendoff/Models/Models.swift.

export type Occasion =
  | 'retirement' | 'new_job' | 'graduation' | 'teacher' | 'season_end' | 'military' | 'farewell';

export type SendoffState = 'draft' | 'collecting' | 'sealed' | 'open';
export type RevealPolicy = 'on_date' | 'manual';
export type ContributionStatus = 'pending' | 'approved' | 'hidden';
export type MediaKind = 'photo' | 'voice' | 'video';
export type MediaStatus = 'uploaded' | 'processing' | 'ready' | 'failed';
export type ThemeID = 'letterpress' | 'midnight_toast' | 'chalk' | 'gold_leaf' | 'darkroom' | 'field_day';

/** What a contributor may know about the Sendoff they were linked to. */
export interface PublicSendoff {
  id: string;
  slug: string;
  recipientName: string;
  occasion: Occasion;
  fromLine: string | null;
  themeId: ThemeID;
  closesAt: Date | null;
  state: SendoffState;
  organizerName: string;
}

/** What the recipient's link reveals about the envelope, before and after it is open. */
export interface RevealSendoff {
  id: string;
  slug: string;
  recipientName: string;
  occasion: Occasion;
  fromLine: string | null;
  coverMessage: string | null;
  themeId: ThemeID;
  musicTrackId: string | null;
  state: SendoffState;
  reveal: RevealPolicy;
  opensAt: Date | null;
  organizerName: string;
  contributorCount: number;
  plan: 'free' | 'single' | 'plus' | 'org';
}

export interface Media {
  id: string;
  kind: MediaKind;
  /** Resolved, playable URL. Null until signed or while processing. */
  url: string | null;
  posterUrl: string | null;
  durationSeconds: number | null;
  transcript: string | null;
  width: number | null;
  height: number | null;
  status: MediaStatus;
  /** Storage path, for signing and for deletes. */
  storagePath: string;
}

export interface Contribution {
  id: string;
  sendoffId: string;
  authorName: string;
  authorRelationship: string | null;
  body: string | null;
  promptUsed: string | null;
  status: ContributionStatus;
  sharedWithGroup: boolean;
  pinned: boolean;
  sortOrder: number | null;
  media: Media[];
  createdAt: Date;
}

/** A file picked or recorded in the browser, before upload. */
export interface LocalMedia {
  id: string;
  kind: MediaKind;
  file: Blob;
  previewUrl: string;
  durationSeconds: number | null;
  width: number | null;
  height: number | null;
  mime: string;
}

export interface ContributionDraft {
  authorName: string;
  authorRelationship: string;
  body: string;
  promptUsed: string | null;
  sharedWithGroup: boolean;
  /** New files to upload. */
  newMedia: LocalMedia[];
  /** Existing media ids to keep when editing. Everything else is removed. */
  keepMediaIds: string[];
}

export interface MusicTrack {
  id: string;
  title: string;
  artist: string | null;
  durationSeconds: number | null;
  /** Playable URL for stock tracks; null for Apple Music linked tracks (app only). */
  url: string | null;
  mood: string | null;
}

export const Limits = {
  videoSeconds: 60,
  voiceSeconds: 120,
  photosPerEntry: 6,
  bodyCharacters: 2000,
  photoBytes: 15 * 1024 * 1024,
  videoBytes: 200 * 1024 * 1024,
} as const;

export class StoreError extends Error {
  constructor(public code: 'not_found' | 'not_allowed' | 'closed' | 'full' | 'sealed' | 'network', message: string) {
    super(message);
  }
}

export const StoreMessages = {
  not_found: "We couldn't find that Sendoff. Check the link you were sent.",
  not_allowed: "This link doesn't open that Sendoff.",
  closed: 'This Sendoff is no longer collecting.',
  full: "This Sendoff is full. Ask the organizer to make room.",
  sealed: "It's sealed. Not yet.",
  network: "Something didn't go through. Try again in a moment.",
} as const;

export function revealOrder(a: Contribution, b: Contribution): number {
  if (a.pinned !== b.pinned) return a.pinned ? -1 : 1;
  if (a.sortOrder != null && b.sortOrder != null) return a.sortOrder - b.sortOrder;
  if (a.sortOrder != null) return -1;
  if (b.sortOrder != null) return 1;
  return a.createdAt.getTime() - b.createdAt.getTime();
}

export function signatureOf(c: Pick<Contribution, 'authorName' | 'authorRelationship'>): string {
  return c.authorRelationship ? `${c.authorName} · ${c.authorRelationship}` : c.authorName;
}

export function firstName(full: string): string {
  return full.trim().split(/\s+/)[0] ?? full;
}

export function initialOf(full: string): string {
  return (full.trim()[0] ?? '?').toUpperCase();
}
