// The one place the public domain lives on the web side. The iOS side reads PUBLIC_HOST from
// ios/Config/Local.xcconfig. Change both when the domain is final.

const env = import.meta.env;

export const Config = {
  supabaseUrl: (env.VITE_SUPABASE_URL as string | undefined) ?? '',
  supabaseAnonKey: (env.VITE_SUPABASE_ANON_KEY as string | undefined) ?? '',
  /** Used for links we print or copy. Falls back to wherever the site is served from. */
  publicOrigin: ((env.VITE_PUBLIC_ORIGIN as string | undefined) || location.origin).replace(/\/$/, ''),
  get hasBackend(): boolean {
    return Boolean(this.supabaseUrl && this.supabaseAnonKey);
  },
};

export function contributeLink(slug: string, token: string | null): string {
  const u = new URL(`/s/${encodeURIComponent(slug)}`, Config.publicOrigin);
  if (token) u.searchParams.set('t', token);
  return u.toString();
}

export function revealLink(slug: string, key: string | null): string {
  const u = new URL(`/s/${encodeURIComponent(slug)}/open`, Config.publicOrigin);
  if (key) u.searchParams.set('k', key);
  return u.toString();
}
