<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api';
  import { currentUser } from '$lib/stores/auth';
  import { goto } from '$app/navigation';
  import type { AlbumSummary } from '$lib/types';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import FavoriteButton from '$lib/components/FavoriteButton.svelte';
  import { player } from '$lib/stores/player';

  let albums: AlbumSummary[] = [];
  let loading = true;
  let error = '';

  // Lazy-auth gate: show login prompt if no session
  $: needsLogin = !$currentUser && !loading;

  async function loadFavorites() {
    loading = true;
    error = '';
    try {
      albums = await api.favorites();
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally {
      loading = false;
    }
  }

  onMount(async () => {
    // Wait for auth state to hydrate before deciding
    await new Promise(r => setTimeout(r, 50));
    if ($currentUser) {
      await loadFavorites();
    } else {
      loading = false;
    }
  });

  // Reload when user logs in
  $: if ($currentUser) {
    loadFavorites();
  }

  async function playAlbum(summary: AlbumSummary) {
    try {
      const album = await api.album(summary.id);
      if (!album.tracks.length) return;
      player.play(album.tracks[0], summary, album.tracks, album.covers);
    } catch {}
  }

  function onFavoriteChange(albumId: string, favorited: boolean) {
    if (!favorited) {
      albums = albums.filter(a => a.id !== albumId);
    }
  }
</script>

<div class="page">
  <div class="header">
    <h1>Favoritos</h1>
    <span class="count">{albums.length > 0 ? `${albums.length} álbumes` : ''}</span>
  </div>

  {#if loading}
    <div class="center"><span class="muted">Cargando…</span></div>

  {:else if needsLogin}
    <div class="center">
      <div class="icon">★</div>
      <p>Inicia sesión para ver tus álbumes favoritos</p>
      <a href="/" class="browse-link">Explorar álbumes →</a>
    </div>

  {:else if error}
    <div class="center"><span class="err">{error}</span></div>

  {:else if albums.length === 0}
    <div class="center">
      <div class="icon">★</div>
      <p class="muted">Sin favoritos todavía</p>
      <p class="hint">Haz click en ★ en cualquier álbum para guardarlo aquí</p>
    </div>

  {:else}
    <div class="grid">
      {#each albums as album (album.id)}
        <div class="card" on:click={() => goto(`/albums/${album.id}`)}
          role="button" tabindex="0"
          on:keydown={(e) => e.key === 'Enter' && goto(`/albums/${album.id}`)}>
          <div class="cover-wrap">
            <CoverImage url={album.coverUrls[0] ?? ''} title={album.title} size={120} radius={8} />
            <div class="overlay">
              <button class="play-btn" on:click|stopPropagation={() => playAlbum(album)}>▶</button>
              <FavoriteButton
                albumId={album.id}
                favorited={true}
                on:change={(e) => onFavoriteChange(album.id, e.detail)}
              />
            </div>
          </div>
          <div class="info">
            <span class="title">{album.title}</span>
            <span class="sub">{album.platform || album.albumType}{album.year ? ` · ${album.year}` : ''}</span>
          </div>
        </div>
      {/each}
    </div>
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
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: var(--sp-md);
  }
  .card {
    display: flex; flex-direction: column; gap: 8px;
    border-radius: var(--r-md); padding: 8px;
    transition: background 0.15s; cursor: pointer;
  }
  .card:hover { background: rgba(255,255,255,0.04); }
  .cover-wrap { border-radius: var(--r-md); overflow: hidden; position: relative; }
  .overlay {
    position: absolute; inset: 0;
    display: flex; align-items: flex-end; justify-content: space-between;
    padding: 8px;
    background: linear-gradient(to top, rgba(0,0,0,0.6) 0%, transparent 50%);
    opacity: 0; transition: opacity 0.15s;
  }
  .cover-wrap:hover .overlay { opacity: 1; }
  .play-btn {
    width: 30px; height: 30px; border-radius: 50%;
    background: rgba(255,255,255,0.9); color: #131320;
    font-size: 12px; display: flex; align-items: center; justify-content: center;
    padding-left: 1px;
  }
  .info { display: flex; flex-direction: column; gap: 2px; }
  .title {
    font-size: 13px; font-weight: 600; color: var(--text);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .sub { font-size: 11px; color: var(--text-muted); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
</style>
