<script lang="ts">
  import { onMount } from 'svelte';
  import { api, pollJob } from '$lib/api';
  import type { CatalogEntry, CatalogConsole, CatalogSyncProgress, SyncedLetter } from '$lib/types';

  const LETTERS = ['', '0-9', ...'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')];

  let entries: CatalogEntry[] = [];
  let consoles: CatalogConsole[] = [];
  let syncProgress: CatalogSyncProgress | null = null;
  let syncedLetters: Record<string, SyncedLetter> = {};
  let syncing = false;
  let syncingLetter = false;
  let syncDoneMsg = '';
  let syncDoneTimer: ReturnType<typeof setTimeout>;
  let loading = false;
  let error = '';
  let total = 0;
  let currentPage = 1;
  const LIMIT = 3000;

  $: totalPages = Math.ceil(total / LIMIT);
  $: pageNums = buildPageNums(currentPage, totalPages);

  function buildPageNums(cur: number, tot: number): (number | null)[] {
    if (tot <= 12) return Array.from({ length: tot }, (_, i) => i + 1);
    const show = new Set([1, tot, cur - 4, cur - 3, cur - 2, cur - 1, cur, cur + 1, cur + 2, cur + 3, cur + 4].filter(n => n >= 1 && n <= tot));
    const sorted = [...show].sort((a, b) => a - b);
    const pages: (number | null)[] = [];
    for (let i = 0; i < sorted.length; i++) {
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) pages.push(null);
      pages.push(sorted[i]);
    }
    return pages;
  }

  let q = '';
  let letter = '';
  let console_ = '';
  let debounceTimer: ReturnType<typeof setTimeout>;

  onMount(async () => {
    try {
      const [c, sp, sl] = await Promise.all([api.catalogConsoles(), api.catalogSyncProgress(), api.syncedLetters()]);
      consoles = c;
      syncProgress = sp;
      syncedLetters = Object.fromEntries(sl.map(s => [s.letter, s]));
      syncing = syncProgress.running;
      if (syncing) pollSync();
    } catch {}
    await load(true);
  });

  async function load(reset = false) {
    if (reset) { currentPage = 1; }
    loading = true;
    error = '';
    try {
      const page = await api.catalog({ q, platform: console_, letter, offset: (currentPage - 1) * LIMIT, limit: LIMIT });
      total = page.total;
      entries = page.items;
    } catch (e) {
      error = e instanceof Error ? e.message : String(e);
    } finally { loading = false; }
  }

  async function goToPage(p: number) {
    currentPage = p;
    await load(false);
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
      syncingLetter = true;
      entries = [];
      total = 0;
      pollSync();
      pollAlbumsDuringSync();
    } catch {}
  }

  async function pollSync() {
    const wasLetterSync = syncingLetter;
    const syncedLetter = letter;
    while (syncing) {
      await new Promise(r => setTimeout(r, 1500));
      try {
        syncProgress = await api.catalogSyncProgress();
        syncing = syncProgress.running;
        if (!syncing) {
          syncingLetter = false;
          await load(true);
          try {
            const sl = await api.syncedLetters();
            syncedLetters = Object.fromEntries(sl.map(s => [s.letter, s]));
          } catch {}
          const errs = syncProgress.errors ? ` (${syncProgress.errors} errores)` : '';
          syncDoneMsg = wasLetterSync
            ? `✓ "${syncedLetter}" lista: ${syncedLetters[syncedLetter]?.entries ?? syncProgress.entries} álbumes${errs}`
            : `✓ Catálogo listo: ${syncProgress.entries} álbumes${errs}`;
          clearTimeout(syncDoneTimer);
          syncDoneTimer = setTimeout(() => (syncDoneMsg = ''), 6000);
        }
      } catch { break; }
    }
  }

  async function pollAlbumsDuringSync() {
    while (syncing && syncingLetter) {
      await new Promise(r => setTimeout(r, 3000));
      if (!syncing || !syncingLetter) break;
      try {
        const page = await api.catalog({ q, platform: console_, letter, offset: 0, limit: LIMIT });
        if (!syncingLetter) break; // guard: pollSync may have finished and reset state while we awaited
        total = page.total;
        entries = page.items;
      } catch {}
    }
  }

  let importing: Record<string, boolean> = {};
  let imported: Record<string, string> = {}; // sourceUrl → albumId

  async function importEntry(entry: CatalogEntry) {
    importing[entry.sourceUrl] = true;
    try {
      const job = await api.addAlbum(entry.sourceUrl);
      if (job.status === 'done') { imported[entry.sourceUrl] = job.albumId; return; }
      await pollJob(job.jobId, (albumId) => { imported[entry.sourceUrl] = albumId; });
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
        <span class="kbd-hint" title="Global catalog search">⌘K</span>
      </div>
      <div class="sync">
        {#if syncDoneMsg}
          <span class="sync-done">{syncDoneMsg}</span>
        {:else if syncProgress}
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
          <button
            class="letter"
            class:sel={letter === l}
            class:synced={!!l && !!syncedLetters[l]}
            title={l && syncedLetters[l] ? `Ya en BD: ${syncedLetters[l].entries} álbumes` : ''}
            on:click={() => setLetter(l)}
          >
            {l || 'All'}{#if l && syncedLetters[l]}<span class="synced-dot">✓</span>{/if}
          </button>
        {/each}
      </div>
      {#if letter}
        <button class="sync-letter-btn" disabled={syncing} on:click={startLetterSync}>
          {syncing ? 'Syncing…' : syncedLetters[letter] ? `Re-sync "${letter}"` : `Sync "${letter}"`}
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

  {#if entries.length === 0 && !loading && !syncingLetter}
    <div class="empty">
      <div class="empty-icon">📦</div>
      <p>{q ? 'No results' : 'Catalog empty'}</p>
      <p class="hint">{q ? 'Try a different search' : 'Press Sync Catalog to fetch albums from khinsider'}</p>
    </div>
  {:else}
    <div class="list">
      {#each entries as entry}
        {@const imp = importing[entry.sourceUrl]}
        {@const albumId = imported[entry.sourceUrl]}
        <div class="entry" class:entry-done={!!albumId}>
          <div class="entry-header">
            {#if albumId}
              <a class="entry-title entry-link" href="/albums/{albumId}">{entry.title}</a>
            {:else}
              <span class="entry-title">{entry.title}</span>
            {/if}
            <div class="entry-action">
              {#if albumId}
                <a class="check" href="/albums/{albumId}" title="Ver álbum">✓</a>
              {:else if imp}
                <span class="muted spin">⟳</span>
              {:else}
                <button class="import-btn" on:click={() => importEntry(entry)} title="Import to library">+</button>
              {/if}
            </div>
          </div>
          <span class="entry-meta">
            {entry.platform || ''}{entry.platform && entry.year ? ' · ' : ''}{entry.year || ''}
          </span>
        </div>
      {/each}
      {#if loading}
        <div class="list-status">Loading…</div>
      {:else if syncingLetter && entries.length > 0}
        <div class="list-status syncing-hint">⟳ fetching more…</div>
      {/if}
    </div>

    {#if !syncingLetter && totalPages > 1}
      <div class="pagination">
        <button class="pg-btn" disabled={currentPage === 1} on:click={() => goToPage(1)}>«</button>
        <button class="pg-btn" disabled={currentPage === 1} on:click={() => goToPage(currentPage - 1)}>‹</button>
        {#each pageNums as p}
          {#if p === null}
            <span class="pg-ellipsis">…</span>
          {:else}
            <button class="pg-btn" class:pg-cur={p === currentPage} on:click={() => goToPage(p)}>{p}</button>
          {/if}
        {/each}
        <button class="pg-btn" disabled={currentPage === totalPages} on:click={() => goToPage(currentPage + 1)}>›</button>
        <button class="pg-btn" disabled={currentPage === totalPages} on:click={() => goToPage(totalPages)}>»</button>
      </div>
    {/if}
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
  .kbd-hint {
    font-size: 10px; color: var(--text-muted);
    padding: 2px 5px;
    background: rgba(255,255,255,0.08);
    border-radius: 4px;
  }
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
  .letter.synced { color: #7ec98f; }
  .letter.synced.sel { color: var(--accent); }
  .synced-dot { color: #4caf50; font-size: 9px; margin-left: 2px; vertical-align: super; }
  .sync-done { font-size: 11px; color: #4caf50; font-weight: 600; animation: fade-in 0.2s ease-out; }
  @keyframes fade-in { from { opacity: 0; } to { opacity: 1; } }
  .console-strip { display: flex; gap: 4px; flex-wrap: wrap; padding-bottom: 2px; max-height: calc(3 * (22px + 4px)); overflow-y: auto; }
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
  .list { flex: 1; overflow-y: auto; display: grid; grid-template-columns: 1fr 1fr; gap: 1px; }
  .entry {
    display: flex;
    flex-direction: column;
    justify-content: center;
    padding: 8px 12px;
    border-bottom: 1px solid var(--border60);
    border-right: 1px solid var(--border60);
    min-height: 40px;
  }
  .entry:nth-child(odd) { border-right: 1px solid var(--border60); }
  .entry:nth-child(even) { border-right: none; }
  .entry:hover { background: rgba(255,255,255,0.02); }
  .entry-header { display: flex; align-items: center; gap: 4px; min-width: 0; flex: 1; }
  .entry-title { font-size: 13px; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .entry-link { color: var(--accent); text-decoration: none; }
  .entry-link:hover { text-decoration: underline; }
  .entry-done .check { color: #4caf50; font-size: 14px; text-decoration: none; }
  .entry-meta { font-size: 11px; color: var(--text-muted); }
  .entry-action { display: flex; align-items: center; justify-content: center; flex-shrink: 0; margin-left: 6px; }
  .import-btn {
    width: 20px; height: 20px;
    border-radius: 50%;
    font-size: 14px;
    color: var(--accent);
    display: flex; align-items: center; justify-content: center;
    opacity: 0;
    flex-shrink: 0;
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
  .list-status { padding: 12px; text-align: center; font-size: 12px; color: var(--text-muted); grid-column: 1 / -1; }
  .syncing-hint { animation: pulse 1.5s ease-in-out infinite; }
  @keyframes pulse { 0%, 100% { opacity: 0.5; } 50% { opacity: 1; } }
  .pagination {
    display: flex; align-items: center; justify-content: center; gap: 4px;
    padding: 10px; border-top: 1px solid var(--separator); flex-shrink: 0;
  }
  .pg-btn {
    min-width: 28px; height: 28px;
    padding: 0 6px;
    border-radius: var(--r-sm);
    font-size: 12px;
    color: var(--text-sec);
    background: rgba(255,255,255,0.04);
  }
  .pg-btn:hover:not(:disabled) { color: var(--text); background: rgba(255,255,255,0.08); }
  .pg-btn:disabled { opacity: 0.3; cursor: default; }
  .pg-btn.pg-cur { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
  .pg-ellipsis { font-size: 12px; color: var(--text-muted); padding: 0 4px; }
</style>
