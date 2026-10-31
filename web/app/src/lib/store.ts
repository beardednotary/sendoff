import { StoreError, type Contribution, type ContributionDraft, type MusicTrack, type PublicSendoff, type RevealSendoff } from './types';
import { Config } from './config';

export type Progress = (fraction: number, label: string) => void;

/** Everything the three web pages need. `MockStore` runs it in memory; `SupabaseStore` for real. */
export interface WebStore {
  readonly isMock: boolean;

  // Contributor (slug + contribute token from the shared link)
  publicSendoff(slug: string, token: string): Promise<PublicSendoff>;
  myContribution(sendoffId: string): Promise<Contribution | null>;
  submit(sendoff: PublicSendoff, draft: ContributionDraft, existing: Contribution | null, onProgress: Progress): Promise<Contribution>;

  // Recipient (slug + recipient key from the reveal link or QR)
  reveal(slug: string, key: string): Promise<RevealSendoff>;
  /** Breaks the seal: flips the Sendoff open if it is due and stamps opened_at. */
  open(slug: string, key: string): Promise<RevealSendoff>;
  /** Approved entries with media URLs resolved. Empty before the Sendoff is open. */
  revealContributions(slug: string, key: string): Promise<Contribution[]>;

  // Catalog
  track(id: string | null): Promise<MusicTrack | null>;
}

let instance: WebStore | undefined;

export async function getStore(): Promise<WebStore> {
  if (instance) return instance;
  const forceMock = new URLSearchParams(location.search).has('mock');
  if (Config.hasBackend && !forceMock) {
    const { SupabaseStore } = await import('./supabase');
    instance = new SupabaseStore(Config.supabaseUrl, Config.supabaseAnonKey);
  } else if (Config.demo || forceMock) {
    const { MockStore } = await import('./mock');
    instance = new MockStore();
  } else {
    instance = new NotYetStore();
  }
  return instance;
}

/** A live site before the backend exists: every link explains itself instead of showing demo data. */
class NotYetStore implements WebStore {
  readonly isMock = false;
  private fail(): never {
    throw new StoreError('not_found', 'Sendoff links start working when the app launches. Check back soon.');
  }
  publicSendoff(): Promise<PublicSendoff> { this.fail(); }
  myContribution(): Promise<Contribution | null> { this.fail(); }
  submit(): Promise<Contribution> { this.fail(); }
  reveal(): Promise<RevealSendoff> { this.fail(); }
  open(): Promise<RevealSendoff> { this.fail(); }
  revealContributions(): Promise<Contribution[]> { this.fail(); }
  async track(): Promise<MusicTrack | null> { return null; }
}
