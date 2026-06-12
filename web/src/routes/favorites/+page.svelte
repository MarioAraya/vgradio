<script lang="ts">
  import { favorites, favoritesGrouped } from '$lib/stores/favorites';
  import { player } from '$lib/stores/player';
  import { api } from '$lib/api';
  import type { Track, AlbumSummary } from '$lib/types';
  import { fmtTime } from '$lib/utils';

  function toTrack(f: import('$lib/types').FavoriteTrack): Track {
    return { id: f.id, name: f.name, index: 0, durationSec: f.durationSec,
      sizeBytes: 0, streamUrl: `/tracks/${f.id}/stream`, downloadUrl: `/tracks/${f.id}/download`, downloaded: false };
  }

  function toSummary(f: import('$lib/types').FavoriteTrack): AlbumSummary {
    return { id: f.albumId, title: f.albumTitle, platform: f.platform, year: f.year,
      albumType: '', trackCount: 0, coverUrls: [] };
  }

  function playAll() {
    const all = $favorites;
    if (!all.length) return;
    const tracks = all.map(toTrack);
    const first = all[0];
    const sum = toSummary(first);
    player.play(tracks[0], sum, tracks);
  }

  function playGroup(tracks: import('$lib/types').FavoriteTrack[], idx: number) {
    const tlist = tracks.map(toTrack);
    const sum = toSummary(tracks[idx]);
    player.play(tlist[idx], sum, tlist);
  }
</script>

<div class="page">
  <div class="header">
    <h1>Favorites</h1>
    {#if $favorites.length > 0}
      <button class="play-all" on:click={playAll}>▶ Play all</button>
    {/if}
  </div>

  {#if $favorites.length === 0}
    <div class="empty">
      <span class="icon">★</span>
      <p>No favorites yet</p>
      <p class="hint">Star tracks in album view to add them here</p>
    </div>
  {:else}
    {#each $favoritesGrouped as group}
      <div class="group">
        <div class="group-header">
          <span class="group-title">{group.albumTitle}</span>
          <span class="group-meta">{group.platform}{group.platform && group.year ? ' · ' : ''}{group.year}</span>
          <button class="rm-all" on:click={() => favorites.removeAll(group.tracks[0].albumId)}>Remove all</button>
        </div>
        {#each group.tracks as fav, i}
          <div class="fav-row">
            <button class="fav-name" on:click={() => playGroup(group.tracks, i)}>{fav.name}</button>
            <span class="fav-dur">{fmtTime(fav.durationSec)}</span>
            <button class="rm" on:click={() => favorites.toggle({ id: fav.id, name: fav.name, index: 0, durationSec: fav.durationSec, sizeBytes: 0, streamUrl: '', downloadUrl: '', downloaded: false }, { id: fav.albumId, title: fav.albumTitle, platform: fav.platform, year: fav.year, albumType: '', trackCount: 0, coverUrls: [] })}>✕</button>
          </div>
        {/each}
      </div>
    {/each}
  {/if}
</div>

<style>
  .page { padding: var(--sp-md); }
  .header { display: flex; align-items: center; gap: 16px; margin-bottom: 20px; }
  h1 { font-size: 22px; font-weight: 700; }
  .play-all {
    padding: 6px 14px;
    background: var(--accent);
    color: #131320;
    border-radius: var(--r-sm);
    font-size: 13px;
    font-weight: 600;
  }
  .empty { display: flex; flex-direction: column; align-items: center; gap: 8px; min-height: 300px; justify-content: center; color: var(--text-muted); }
  .icon { font-size: 36px; opacity: 0.4; }
  .hint { font-size: 12px; }
  .group { margin-bottom: 20px; }
  .group-header {
    display: flex;
    align-items: baseline;
    gap: 8px;
    padding: 6px 0;
    border-bottom: 1px solid var(--separator);
    margin-bottom: 4px;
  }
  .group-title { font-size: 14px; font-weight: 600; }
  .group-meta { font-size: 12px; color: var(--text-muted); flex: 1; }
  .rm-all { font-size: 11px; color: var(--text-muted); }
  .rm-all:hover { color: var(--red); }
  .fav-row { display: flex; align-items: center; padding: 5px 8px; border-radius: var(--r-sm); }
  .fav-row:hover { background: rgba(255,255,255,0.04); }
  .fav-name { flex: 1; text-align: left; font-size: 13px; color: var(--text); }
  .fav-name:hover { color: var(--accent); }
  .fav-dur { font-size: 12px; color: var(--text-muted); margin-right: 8px; font-variant-numeric: tabular-nums; }
  .rm { font-size: 12px; color: var(--text-muted); opacity: 0; }
  .fav-row:hover .rm { opacity: 1; }
  .rm:hover { color: var(--red); }
</style>
