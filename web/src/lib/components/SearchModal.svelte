<script lang="ts">
  import { createEventDispatcher, tick } from 'svelte';
  import { goto } from '$app/navigation';
  import { api } from '$lib/api';
  import type { AlbumSummary } from '$lib/types';
  import CoverImage from './CoverImage.svelte';

  export let open = false;

  const dispatch = createEventDispatcher<{ close: void }>();

  let query = '';
  let albums: AlbumSummary[] = [];
  let filtered: AlbumSummary[] = [];
  let cursor = 0;
  let input: HTMLInputElement;
  let loaded = false;

  $: if (open) {
    query = '';
    cursor = 0;
    tick().then(() => input?.focus());
    if (!loaded) loadAlbums();
  }

  async function loadAlbums() {
    try {
      albums = await api.albums();
      loaded = true;
    } catch {}
  }

  $: {
    const q = query.trim().toLowerCase();
    filtered = q
      ? albums.filter(a =>
          a.title.toLowerCase().includes(q) ||
          (a.platform && a.platform.toLowerCase().includes(q))
        ).slice(0, 12)
      : albums.slice(0, 12);
    cursor = 0;
  }

  function close() {
    open = false;
    dispatch('close');
  }

  function select(album: AlbumSummary) {
    close();
    goto(`/albums/${album.id}`);
  }

  function handleKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') { close(); return; }
    if (e.key === 'ArrowDown') { e.preventDefault(); cursor = Math.min(cursor + 1, filtered.length - 1); }
    if (e.key === 'ArrowUp') { e.preventDefault(); cursor = Math.max(cursor - 1, 0); }
    if (e.key === 'Enter' && filtered[cursor]) { select(filtered[cursor]); }
  }
</script>

{#if open}
  <div class="backdrop" on:click={close} role="presentation">
    <div class="modal" on:click|stopPropagation role="dialog" aria-modal="true" aria-label="Buscar álbum">
      <div class="search-row">
        <span class="icon">⌕</span>
        <input
          bind:this={input}
          bind:value={query}
          on:keydown={handleKeydown}
          type="text"
          placeholder="Buscar álbum…"
          autocomplete="off"
          spellcheck="false"
        />
        {#if query}
          <button class="clear" on:click={() => { query = ''; input.focus(); }}>×</button>
        {/if}
      </div>

      {#if filtered.length > 0}
        <ul class="results" role="listbox">
          {#each filtered as album, i (album.id)}
            <li
              class="result"
              class:active={i === cursor}
              role="option"
              aria-selected={i === cursor}
              on:click={() => select(album)}
              on:mouseenter={() => cursor = i}
            >
              <CoverImage url={album.coverUrls[0] ?? ''} title={album.title} size={36} radius={4} />
              <div class="info">
                <span class="title">{album.title}</span>
                <span class="sub">{album.platform || ''}{album.year ? (album.platform ? ' · ' : '') + album.year : ''}</span>
              </div>
            </li>
          {/each}
        </ul>
      {:else if query}
        <div class="empty">Sin resultados para «{query}»</div>
      {/if}

      <div class="hint">
        <span>↑↓ navegar</span>
        <span>↵ abrir</span>
        <span>Esc cerrar</span>
      </div>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed; inset: 0; z-index: 200;
    background: rgba(0,0,0,0.55);
    display: flex; align-items: flex-start; justify-content: center;
    padding-top: 80px;
  }
  .modal {
    background: var(--surface);
    border: 1px solid var(--separator);
    border-radius: var(--r-lg, 12px);
    width: 560px; max-width: calc(100vw - 32px);
    box-shadow: 0 20px 60px rgba(0,0,0,0.6);
    overflow: hidden;
  }
  .search-row {
    display: flex; align-items: center; gap: 10px;
    padding: 14px 16px;
    border-bottom: 1px solid var(--separator);
  }
  .icon { font-size: 18px; color: var(--text-muted); flex-shrink: 0; }
  input {
    flex: 1;
    font-size: 16px;
    background: transparent;
    color: var(--text);
    border: none; outline: none;
  }
  input::placeholder { color: var(--text-muted); }
  .clear {
    font-size: 18px; color: var(--text-muted); line-height: 1;
    width: 24px; height: 24px;
    display: flex; align-items: center; justify-content: center;
    border-radius: 50%;
  }
  .clear:hover { color: var(--text); background: rgba(255,255,255,0.08); }
  .results {
    list-style: none;
    max-height: 380px;
    overflow-y: auto;
    padding: 6px;
  }
  .result {
    display: flex; align-items: center; gap: 10px;
    padding: 6px 8px;
    border-radius: var(--r-sm);
    cursor: pointer;
  }
  .result.active { background: rgba(255,255,255,0.07); }
  .info { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
  .title {
    font-size: 13px; font-weight: 500; color: var(--text);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  }
  .sub { font-size: 11px; color: var(--text-muted); }
  .empty { padding: 20px 16px; font-size: 13px; color: var(--text-muted); text-align: center; }
  .hint {
    display: flex; gap: 16px;
    padding: 8px 16px;
    border-top: 1px solid var(--separator);
    font-size: 11px; color: var(--text-muted);
  }
</style>
