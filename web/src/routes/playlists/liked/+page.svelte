<script lang="ts">
  import { api } from '$lib/api';
  import { currentUser, authLoading } from '$lib/stores/auth';
  import { player } from '$lib/stores/player';
  import { addToast } from '$lib/stores/toasts';
  import { setTrackFavorited } from '$lib/stores/trackFavorites';
  import { fmtTime } from '$lib/utils';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import { goto } from '$app/navigation';
  import type { FavoriteTrack } from '$lib/types';

  let tracks: FavoriteTrack[] = [];
  let favLoading = false;

  $: loading = $authLoading || favLoading;
  $: needsLogin = !$authLoading && !$currentUser;
  $: totalSec = tracks.reduce((s, t) => s + t.durationSec, 0);

  async function loadFavorites() {
    favLoading = true;
    try { tracks = await api.favoriteTracks(); }
    catch { /* ignore */ }
    finally { favLoading = false; }
  }

  $: if (!$authLoading && $currentUser) loadFavorites();

  function asTrack(t: FavoriteTrack, idx: number) {
    return { id: t.id, index: idx, name: t.name, durationSec: t.durationSec,
      sizeBytes: 0, streamUrl: `/tracks/${t.id}/stream`,
      downloadUrl: `/tracks/${t.id}/download`, downloaded: false };
  }

  async function playAll() {
    if (!tracks.length) return;
    const allTracks = tracks.map(asTrack);
    const summary = {
      id: '__liked__', title: 'Liked Music', platform: '', year: 0,
      albumType: '', trackCount: tracks.length, totalDurationSec: totalSec, coverUrls: []
    };
    player.play(allTracks[0], summary, allTracks);
  }

  async function playFrom(t: FavoriteTrack) {
    try {
      const album = await api.album(t.albumId);
      const summary = { id: album.id, title: album.title, platform: album.platform,
        year: album.year, albumType: album.albumType, trackCount: album.tracks.length,
        totalDurationSec: album.tracks.reduce((s, tr) => s + tr.durationSec, 0),
        coverUrls: album.covers.map(c => c.url) };
      const track = album.tracks.find(tr => tr.id === t.id);
      if (track) player.play(track, summary, album.tracks, album.covers);
    } catch { addToast('Error loading track', 'error'); }
  }

  async function unfavorite(t: FavoriteTrack) {
    try {
      await api.toggleTrackFavorite(t.id);
      setTrackFavorited(t.id, false);
      tracks = tracks.filter(tr => tr.id !== t.id);
    } catch { addToast('Error', 'error'); }
  }

  $: grouped = (() => {
    const map = new Map<string, { albumId: string; albumTitle: string; platform: string; year: number; coverUrl: string; tracks: FavoriteTrack[] }>();
    for (const t of tracks) {
      if (!map.has(t.albumId))
        map.set(t.albumId, { albumId: t.albumId, albumTitle: t.albumTitle, platform: t.platform, year: t.year, coverUrl: t.coverUrl ?? '', tracks: [] });
      map.get(t.albumId)!.tracks.push(t);
    }
    return [...map.values()];
  })();

  function fmtDuration(sec: number) {
    const h = Math.floor(sec / 3600);
    const m = Math.floor((sec % 3600) / 60);
    return h > 0 ? `${h}h ${m}m` : `${m}m`;
  }
</script>

<div class="page">
  {#if loading}
    <div class="center"><span class="muted">Cargando…</span></div>

  {:else if needsLogin}
    <div class="center">
      <div class="big-icon">★</div>
      <p>Inicia sesión para ver tus canciones favoritas</p>
    </div>

  {:else}
    <div class="hero">
      <div class="hero-cover">
        {#if grouped.slice(0,4).some(g => g.coverUrl)}
          <div class="mosaic">
            {#each grouped.slice(0,4) as g}
              <CoverImage url={g.coverUrl} title={g.albumTitle} size={80} radius={0} />
            {/each}
          </div>
        {:else}
          <div class="cover-placeholder">★</div>
        {/if}
      </div>
      <div class="hero-info">
        <span class="auto-badge">Auto playlist</span>
        <h1>Liked Music</h1>
        {#if $currentUser}<span class="owner">@{$currentUser.username}</span>{/if}
        <span class="meta">{tracks.length} tracks{tracks.length ? ` · ${fmtDuration(totalSec)}` : ''}</span>
        <div class="actions">
          <button class="play-btn" on:click={playAll} disabled={!tracks.length}>▶ Play all</button>
        </div>
      </div>
    </div>

    {#if tracks.length === 0}
      <div class="center">
        <div class="big-icon">★</div>
        <p class="muted">Sin canciones favoritas todavía</p>
        <p class="hint">Haz click en ☆ junto a cualquier canción en un álbum</p>
      </div>
    {:else}
      {#each grouped as group (group.albumId)}
        <div class="album-group">
          <div class="album-header" role="button" tabindex="0"
            on:click={() => goto(`/albums/${group.albumId}`)}
            on:keydown={e => e.key === 'Enter' && goto(`/albums/${group.albumId}`)}>
            <CoverImage url={group.coverUrl} title={group.albumTitle} size={36} radius={4} />
            <div class="album-meta">
              <span class="album-title">{group.albumTitle}</span>
              <span class="album-sub">{group.platform}{group.year ? ` · ${group.year}` : ''}</span>
            </div>
          </div>
          <div class="track-list">
            {#each group.tracks as track (track.id)}
              <div class="track-row">
                <button class="track-name" on:click={() => playFrom(track)}>{track.name}</button>
                <span class="track-dur">{fmtTime(track.durationSec)}</span>
                <button class="unfav" title="Quitar de favoritos" on:click={() => unfavorite(track)}>★</button>
              </div>
            {/each}
          </div>
        </div>
      {/each}
    {/if}
  {/if}
</div>

<style>
  .page { padding: var(--sp-md); max-width: 860px; }
  .center { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 10px; min-height: 300px; color: var(--text-muted); }
  .big-icon { font-size: 48px; opacity: 0.3; }
  .muted { color: var(--text-muted); }
  .hint { font-size: 12px; color: var(--text-muted); }

  .hero { display: flex; gap: 24px; align-items: flex-end; margin-bottom: 32px; padding-bottom: 24px; border-bottom: 1px solid var(--separator); }
  .hero-cover { flex-shrink: 0; }
  .mosaic { display: grid; grid-template-columns: 1fr 1fr; width: 160px; height: 160px; border-radius: var(--r-lg); overflow: hidden; }
  .cover-placeholder { width: 160px; height: 160px; border-radius: var(--r-lg); background: var(--surface-hi); display: flex; align-items: center; justify-content: center; font-size: 48px; opacity: 0.3; }
  .hero-info { display: flex; flex-direction: column; gap: 6px; }
  .auto-badge { font-size: 10px; text-transform: uppercase; letter-spacing: 0.08em; color: var(--text-sec); }
  h1 { font-size: 28px; font-weight: 800; }
  .owner { font-size: 12px; color: var(--text-sec); }
  .meta { font-size: 12px; color: var(--text-sec); }
  .actions { margin-top: 10px; }
  .play-btn { padding: 10px 28px; background: var(--accent); color: #000; border-radius: 999px; font-size: 14px; font-weight: 700; }
  .play-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .play-btn:not(:disabled):hover { opacity: 0.88; }

  .album-group { margin-bottom: var(--sp-lg); }
  .album-header { display: flex; align-items: center; gap: 10px; padding: 6px 0; cursor: pointer; margin-bottom: 4px; }
  .album-header:hover .album-title { color: var(--accent); }
  .album-meta { display: flex; flex-direction: column; }
  .album-title { font-size: 13px; font-weight: 600; }
  .album-sub { font-size: 11px; color: var(--text-sec); }
  .track-list { display: flex; flex-direction: column; gap: 1px; }
  .track-row { display: flex; align-items: center; gap: 8px; padding: 6px 8px; border-radius: var(--r-sm); }
  .track-row:hover { background: var(--surface-hi); }
  .track-name { flex: 1; text-align: left; font-size: 13px; color: var(--text); }
  .track-name:hover { color: var(--accent); }
  .track-dur { font-size: 11px; color: var(--text-sec); min-width: 36px; text-align: right; }
  .unfav { font-size: 14px; color: var(--accent); opacity: 0.7; padding: 2px 4px; }
  .unfav:hover { opacity: 1; }
</style>
