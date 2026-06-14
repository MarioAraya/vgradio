<script lang="ts">
  import { api } from '$lib/api';
  import { currentUser, authLoading } from '$lib/stores/auth';
  import type { FavoriteTrack } from '$lib/types';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import { player } from '$lib/stores/player';
  import { fmtTime } from '$lib/utils';
  import { goto } from '$app/navigation';
  import { addToast } from '$lib/stores/toasts';
  import { setTrackFavorited } from '$lib/stores/trackFavorites';

  let tracks: FavoriteTrack[] = [];
  let favLoading = false;
  let error = '';

  $: loading = $authLoading || favLoading;
  $: needsLogin = !$authLoading && !$currentUser;

  async function loadFavorites() {
    favLoading = true;
    error = '';
    try {
      tracks = await api.favoriteTracks();
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      favLoading = false;
    }
  }

  $: if (!$authLoading && $currentUser) {
    loadFavorites();
  }

  async function playTrack(t: FavoriteTrack) {
    try {
      const album = await api.album(t.albumId);
      const summary = { id: album.id, title: album.title, platform: album.platform,
        year: album.year, albumType: album.albumType, trackCount: album.tracks.length,
        coverUrls: album.covers.map(c => c.url) };
      const track = album.tracks.find(tr => tr.id === t.id);
      if (!track) return;
      player.play(track, summary, album.tracks, album.covers);
    } catch {}
  }

  async function unfavorite(t: FavoriteTrack) {
    try {
      await api.toggleTrackFavorite(t.id);
      setTrackFavorited(t.id, false);
      tracks = tracks.filter(tr => tr.id !== t.id);
    } catch (e) {
      addToast('Error al eliminar favorito', 'error');
    }
  }

  // Group tracks by album
  $: grouped = (() => {
    const map = new Map<string, { albumId: string; albumTitle: string; platform: string; year: number; coverUrl: string; tracks: FavoriteTrack[] }>();
    for (const t of tracks) {
      if (!map.has(t.albumId)) {
        map.set(t.albumId, { albumId: t.albumId, albumTitle: t.albumTitle,
          platform: t.platform, year: t.year, coverUrl: t.coverUrl ?? '', tracks: [] });
      }
      map.get(t.albumId)!.tracks.push(t);
    }
    return [...map.values()];
  })();
</script>

<div class="page">
  <div class="header">
    <h1>Favoritos</h1>
    <span class="count">{tracks.length > 0 ? `${tracks.length} canciones` : ''}</span>
  </div>

  {#if loading}
    <div class="center"><span class="muted">Cargando…</span></div>

  {:else if needsLogin}
    <div class="center">
      <div class="icon">★</div>
      <p>Inicia sesión para ver tus canciones favoritas</p>
      <a href="/" class="browse-link">Explorar álbumes →</a>
    </div>

  {:else if error}
    <div class="center"><span class="err">{error}</span></div>

  {:else if tracks.length === 0}
    <div class="center">
      <div class="icon">★</div>
      <p class="muted">Sin favoritos todavía</p>
      <p class="hint">Haz click en ☆ junto a cualquier canción en un álbum</p>
    </div>

  {:else}
    {#each grouped as group (group.albumId)}
      <div class="album-group">
        <div class="album-header" role="button" tabindex="0"
          on:click={() => goto(`/albums/${group.albumId}`)}
          on:keydown={(e) => e.key === 'Enter' && goto(`/albums/${group.albumId}`)}>
          <CoverImage url={group.coverUrl} title={group.albumTitle} size={40} radius={4} />
          <div class="album-meta">
            <span class="album-title">{group.albumTitle}</span>
            <span class="album-sub">{group.platform}{group.year ? ` · ${group.year}` : ''}</span>
          </div>
        </div>
        <div class="track-list">
          {#each group.tracks as track (track.id)}
            <div class="track-row">
              <button class="track-name" on:click={() => playTrack(track)}>{track.name}</button>
              <span class="track-dur">{fmtTime(track.durationSec)}</span>
              <button class="unfav" title="Quitar de favoritos" on:click={() => unfavorite(track)}>★</button>
            </div>
          {/each}
        </div>
      </div>
    {/each}
  {/if}
</div>

<style>
  .page { padding: var(--sp-md); }
  .header { display: flex; align-items: baseline; gap: 10px; margin-bottom: var(--sp-lg); }
  h1 { font-size: 22px; font-weight: 700; }
  .count { font-size: 12px; color: var(--text-muted); }
  .center {
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    gap: 10px; min-height: 300px; color: var(--text-muted);
  }
  .icon { font-size: 36px; opacity: 0.4; }
  .muted { color: var(--text-muted); }
  .err { color: var(--red); font-size: 13px; }
  .hint { font-size: 12px; }
  .browse-link { font-size: 13px; color: var(--accent); text-decoration: underline; }

  .album-group { margin-bottom: var(--sp-lg); }
  .album-header {
    display: flex; align-items: center; gap: 10px;
    padding: 8px; border-radius: var(--r-sm);
    cursor: pointer; margin-bottom: 4px;
  }
  .album-header:hover { background: rgba(255,255,255,0.04); }
  .album-meta { display: flex; flex-direction: column; gap: 2px; }
  .album-title { font-size: 14px; font-weight: 600; color: var(--text); }
  .album-sub { font-size: 11px; color: var(--text-muted); }

  .track-list { padding-left: 50px; }
  .track-row {
    display: grid;
    grid-template-columns: 1fr 52px 32px;
    align-items: center;
    padding: 5px 8px;
    border-radius: var(--r-sm);
    height: 36px;
  }
  .track-row:hover { background: rgba(255,255,255,0.04); }
  .track-name {
    text-align: left; font-size: 13px; color: var(--text);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    padding-right: 8px;
  }
  .track-name:hover { color: var(--accent); }
  .track-dur { font-size: 12px; color: var(--text-muted); font-variant-numeric: tabular-nums; }
  .unfav {
    font-size: 14px; color: var(--accent);
    width: 28px; height: 28px;
    display: flex; align-items: center; justify-content: center;
    border-radius: var(--r-sm);
    opacity: 0;
    transition: opacity 0.1s;
  }
  .track-row:hover .unfav { opacity: 1; }
  .unfav:hover { background: rgba(203,168,39,0.12); }
</style>
