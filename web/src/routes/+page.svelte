<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api';
  import { goto } from '$app/navigation';
  import type { AlbumSummary } from '$lib/types';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import { letterGradient } from '$lib/utils';

  let albums: AlbumSummary[] = [];
  let loading = true;
  let error = '';

  onMount(async () => {
    try { albums = await api.albums(); }
    catch (e) { error = e instanceof Error ? e.message : String(e); }
    finally { loading = false; }
  });
</script>

<div class="page">
  <div class="header">
    <h1>Library</h1>
    <span class="count">{albums.length} albums</span>
  </div>

  {#if loading}
    <div class="center"><span class="muted">Loading…</span></div>
  {:else if error}
    <div class="center"><span class="err">{error}</span></div>
  {:else if albums.length === 0}
    <div class="center">
      <div class="empty-icon">♫</div>
      <p class="muted">No albums yet</p>
      <p class="hint">Add albums with + Add URL (Cmd+4)</p>
    </div>
  {:else}
    <div class="grid">
      {#each albums as album}
        <button class="card" on:click={() => goto(`/albums/${album.id}`)}>
          <div class="cover-wrap">
            <CoverImage url={album.coverUrls[0] ?? ''} title={album.title} size={120} radius={8} />
          </div>
          <div class="card-info">
            <span class="card-title">{album.title}</span>
            <span class="card-sub">{album.platform || album.albumType}{album.year ? ` · ${album.year}` : ''}</span>
          </div>
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .page { padding: var(--sp-md); }
  .header {
    display: flex;
    align-items: baseline;
    gap: 10px;
    margin-bottom: var(--sp-lg);
  }
  h1 { font-size: 22px; font-weight: 700; }
  .count { font-size: 12px; color: var(--text-muted); }
  .center {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-height: 300px;
    color: var(--text-muted);
  }
  .empty-icon { font-size: 40px; opacity: 0.4; }
  .muted { color: var(--text-muted); }
  .err { color: var(--red); font-size: 13px; }
  .hint { font-size: 12px; color: var(--text-muted); }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: var(--sp-md);
  }
  .card {
    display: flex;
    flex-direction: column;
    gap: 8px;
    text-align: left;
    border-radius: var(--r-md);
    padding: 8px;
    transition: background 0.15s;
  }
  .card:hover { background: rgba(255,255,255,0.04); }
  .cover-wrap { border-radius: var(--r-md); overflow: hidden; }
  .card-info { display: flex; flex-direction: column; gap: 2px; }
  .card-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .card-sub { font-size: 11px; color: var(--text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
</style>
