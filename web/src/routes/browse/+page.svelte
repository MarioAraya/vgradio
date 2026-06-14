<script lang="ts">
  import { onMount } from 'svelte';
  import { api, pollJob } from '$lib/api';
  import type { CatalogEntry, CatalogConsole, CatalogSyncProgress } from '$lib/types';

  const LETTERS = ['', '0-9', ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')];

  let entries: CatalogEntry[] = [];
  let consoles: CatalogConsole[] = [];
  let syncProgress: CatalogSyncProgress | null = null;
  let syncing = false;
  let loading = false;
  let error = '';
  let total = 0;
  let offset = 0;
  const LIMIT = 50;

  let q = '';
  let letter = '';
  let console_ = '';
  let debounceTimer: ReturnType<typeof setTimeout>;

  onMount(async () => {
    try {
      [consoles, syncProgress] = await Promise.all([api.catalogConsoles(), api.catalogSyncProgress()]);
      syncing = syncProgress.running;
      if (syncing) pollSync();
    } catch {}
    await load(true);
  });

  async function load(reset = false) {
    if (reset) { entries = []; offset = 0; }
    loading = true;
    error = '';
    try {
      const page = await api.catalog({ q, platform: console_, letter, offset, limit: LIMIT });
      total = page.total;
      entries = reset ? page.items : [...entries, ...page.items];
      offset = entries.length;
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally { loading = false; }
  }

  function onSearch() {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => load(true), 300);
  }

  function setLetter(l: string) { letter = l; load(true); }
  function setConsole(c: string) { console_ = c; load(true); }

  async function startSync() {
    try {
      await api.startCatalogSync();
      syncing = true;
      pollSync();
    } catch {}
  }

  async function startLetterSync() {
    if (!letter) return;
    try {
      await api.startLetterSync(letter);
      syncing = true;
      pollSync();
    } catch {}
  }

  async function pollSync() {
    while (syncing) {
      await new Promise(r => setTimeout(r, 1500));
      try {
        syncProgress = await api.catalogSyncProgress();
        syncing = syncProgress.running;
        if (!syncing) await load(true);
      } catch { break; }
    }
  }

  let importing: Record<string, boolean> = {};
  let imported: Record<string, boolean> = {};

  async function importEntry(entry: CatalogEntry) {
    importing[entry.sourceUrl] = true;
    try {
      const job = await api.addAlbum(entry.sourceUrl);
      if (job.status === 'done') { imported[entry.sourceUrl] = true; return; }
      await pollJob(job.jobId, () => { imported[entry.sourceUrl] = true; });
    } catch {}
    importing[entry.sourceUrl] = false;
  }
</script>

<div class="page">
  <div class="toolbar">
    <div class="search-row">
      <div class="search-input">
        <span>🔍</span>
        <input type="text" placeholder="Search albums…" bind:value={q} on:input={onSearch} />
      </div>
      <div class="sync">
        {#if syncProgress}
          {#if syncing}
            <span class="muted">⟳ {syncProgress.done}/{syncProgress.total} · {syncProgress.entries} entries</span>
          {:else}
            <span class="muted">✓ {syncProgress.entries} albums · {syncProgress.consoles} consoles</span>
          {/if}
        {/if}
        <button class="sync-btn" on:click={startSync} disabled={syncing}>
          {syncing ? 'Syncing…' : 'Sync Catalog'}
        </button>
      </div>
    </div>

    <div class="letter-row">
      <div class="letter-strip">
        {#each LETTERS as l}
          <button class="letter" class:sel={letter === l} on:click={() => setLetter(l)}>
            {l || 'All'}
          </button>
        {/each}
      </div>
      {#if letter}
        <button class="sync-letter-btn" disabled={syncing} on:click={startLetterSync}>
          {syncing ? 'Syncing…' : `Sync "${letter}"`}
        </button>
      {/if}
    </div>

    {#if consoles.length > 0}
      <div class="console-strip">
        <button class="chip" class:sel={console_ === ''} on:click={() => setConsole('')}>All</button>
        {#each consoles as c}
          <button class="chip" class:sel={console_ === c.name} on:click={() => setConsole(c.name)}>
            {c.name} ({c.albumCount})
          </button>
        {/each}
      </div>
    {/if}
  </div>

  {#if error}
    <div class="err-banner">{error}</div>
  {/if}

  {#if entries.length === 0 && !loading}
    <div class="empty">
      <div class="empty-icon">📦</div>
      <p>{q ? 'No results' : 'Catalog empty'}</p>
      <p class="hint">{q ? 'Try a different search' : 'Press Sync Catalog to fetch albums from khinsider'}</p>
    </div>
  {:else}
    <div class="list">
      {#each entries as entry}
        {@const imp = importing[entry.sourceUrl]}
        {@const done = imported[entry.sourceUrl]}
        <div class="entry">
          <div class="entry-info">
            <span class="entry-title">{entry.title}</span>
            <span class="entry-meta">
              {entry.platform || ''}{entry.platform && entry.year ? ' · ' : ''}{entry.year || ''}
            </span>
          </div>
          <div class="entry-action">
            {#if done}
              <span class="check">✓</span>
            {:else if imp}
              <span class="muted spin">⟳</span>
            {:else}
              <button class="import-btn" on:click={() => importEntry(entry)} title="Import to library">+</button>
            {/if}
          </div>
        </div>
      {/each}
      {#if loading}
        <div class="loading">Loading…</div>
      {/if}
      {#if !loading && entries.length < total}
        <button class="load-more" on:click={() => load()}>Load more</button>
      {/if}
    </div>
  {/if}
</div>

<style>
  .page { display: flex; flex-direction: column; height: 100%; overflow: hidden; }
  .toolbar { padding: var(--sp-sm) var(--sp-md); border-bottom: 1px solid var(--separator); display: flex; flex-direction: column; gap: 6px; }
  .search-row { display: flex; align-items: center; gap: var(--sp-sm); }
  .search-input {
    display: flex; align-items: center; gap: 6px;
    padding: 6px 10px;
    background: rgba(255,255,255,0.05);
    border-radius: var(--r-md);
    flex: 1; max-width: 280px;
  }
  .search-input input { flex: 1; }
  .sync { display: flex; align-items: center; gap: 8px; margin-left: auto; }
  .muted { font-size: 11px; color: var(--text-muted); }
  .sync-btn {
    font-size: 12px;
    color: var(--accent);
    padding: 5px 10px;
    border-radius: var(--r-sm);
    background: var(--accent-soft);
  }
  .sync-btn:disabled { opacity: 0.5; }
  .letter-row { display: flex; align-items: center; gap: 8px; }
  .letter-strip { display: flex; gap: 2px; overflow-x: auto; padding-bottom: 2px; flex: 1; }
  .sync-letter-btn {
    flex-shrink: 0; font-size: 12px; color: var(--accent);
    padding: 4px 10px; border-radius: var(--r-sm); background: var(--accent-soft); white-space: nowrap;
  }
  .sync-letter-btn:hover:not(:disabled) { background: rgba(203,168,39,0.18); }
  .sync-letter-btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .letter {
    font-size: 11px;
    padding: 2px 6px;
    border-radius: var(--r-sm);
    color: var(--text-sec);
    white-space: nowrap;
    flex-shrink: 0;
  }
  .letter:hover { color: var(--text); background: rgba(255,255,255,0.04); }
  .letter.sel { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
  .console-strip { display: flex; gap: 4px; flex-wrap: wrap; padding-bottom: 2px; max-height: calc(3 * (22px + 4px)); overflow: hidden; }
  .chip {
    font-size: 11px;
    padding: 3px 10px;
    border-radius: 20px;
    color: var(--text-sec);
    background: rgba(255,255,255,0.04);
    white-space: nowrap;
    flex-shrink: 0;
  }
  .chip:hover { color: var(--text); }
  .chip.sel { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
  .err-banner { padding: 8px 16px; background: rgba(224,85,85,0.15); color: var(--red); font-size: 12px; }
  .list { flex: 1; overflow-y: auto; }
  .entry {
    display: flex;
    align-items: center;
    padding: 8px 16px;
    border-bottom: 1px solid var(--border60);
    height: 40px;
  }
  .entry:hover { background: rgba(255,255,255,0.02); }
  .entry-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 1px; }
  .entry-title { font-size: 13px; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .entry-meta { font-size: 11px; color: var(--text-muted); }
  .entry-action { width: 28px; display: flex; align-items: center; justify-content: center; }
  .import-btn {
    width: 22px; height: 22px;
    border-radius: 50%;
    font-size: 16px;
    color: var(--accent);
    display: flex; align-items: center; justify-content: center;
    opacity: 0;
  }
  .entry:hover .import-btn { opacity: 1; }
  .check { color: #4caf50; font-size: 14px; }
  .spin { display: inline-block; animation: spin 1s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .empty {
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    gap: 8px; min-height: 300px; color: var(--text-muted);
  }
  .empty-icon { font-size: 36px; opacity: 0.4; }
  .hint { font-size: 12px; }
  .loading, .load-more { padding: 12px; text-align: center; font-size: 12px; color: var(--text-muted); }
  .load-more { color: var(--accent); cursor: pointer; }
  .load-more:hover { text-decoration: underline; }
</style>
