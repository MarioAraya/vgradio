<script lang="ts">
  import { onMount } from 'svelte';
  import { api } from '$lib/api';
  import { goto } from '$app/navigation';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import type { LibraryStats, DownloadedAlbum } from '$lib/types';

  // --- Section 1: Connection ---
  let backendURL = '';
  let testStatus: 'idle' | 'testing' | 'ok' | 'error' = 'idle';
  let testMsg = '';

  function loadBackendURL() {
    backendURL = localStorage.getItem('vgradio.backendURL') ?? api.baseURL();
  }

  function saveBackendURL() {
    localStorage.setItem('vgradio.backendURL', backendURL.trim());
  }

  async function testConnection() {
    testStatus = 'testing';
    testMsg = '';
    try {
      const res = await fetch(backendURL.trim() + '/stats');
      if (res.ok) {
        testStatus = 'ok';
        testMsg = 'Conectado';
      } else {
        testStatus = 'error';
        testMsg = `HTTP ${res.status}`;
      }
    } catch (e) {
      testStatus = 'error';
      testMsg = (e as Error).message;
    }
  }

  // --- Section CF Clearance ---
  let cfValue = '';
  let cfStatus: 'idle' | 'ok' | 'error' = 'idle';

  async function saveCF() {
    if (!cfValue.trim()) return;
    try {
      await api.setCFClearance(cfValue.trim());
      cfStatus = 'ok';
      cfValue = '';
    } catch { cfStatus = 'error'; }
  }

  // --- Section 2: Downloaded albums ---
  let dlAlbums: DownloadedAlbum[] = [];
  let dlLoading = true;
  let deleting = new Set<string>();

  async function loadDownloads() {
    dlLoading = true;
    try { dlAlbums = await api.downloadedAlbums(); } catch {}
    dlLoading = false;
  }

  async function deleteLocal(album: DownloadedAlbum) {
    deleting = new Set([...deleting, album.id]);
    try {
      await api.deleteAlbumLocal(album.id);
      dlAlbums = dlAlbums.filter(a => a.id !== album.id);
      stats = stats ? { ...stats, downloaded: stats.downloaded - album.downloaded } : stats;
    } catch {}
    deleting = new Set([...deleting].filter(id => id !== album.id));
  }

  // --- Section 3: Stats + scrape pending ---
  let stats: LibraryStats | null = null;
  let statsLoading = true;
  let scraping = false;
  let scrapeResult: { resolved: number; failed: number; total: number } | null = null;

  async function loadStats() {
    statsLoading = true;
    try { stats = await api.stats(); } catch {}
    statsLoading = false;
  }

  async function scrapeAllPending() {
    scraping = true;
    scrapeResult = null;
    try {
      scrapeResult = await api.scrapeAllPending();
      await loadStats();
    } catch {}
    scraping = false;
  }

  function fmtBytes(b: number): string {
    if (b < 1024) return `${b} B`;
    if (b < 1024 * 1024) return `${(b / 1024).toFixed(1)} KB`;
    if (b < 1024 * 1024 * 1024) return `${(b / 1024 / 1024).toFixed(1)} MB`;
    return `${(b / 1024 / 1024 / 1024).toFixed(2)} GB`;
  }

  onMount(() => {
    loadBackendURL();
    loadDownloads();
    loadStats();
  });
</script>

<div class="page">
  <h1>Settings</h1>

  <!-- ─── Section 1: Connection ─── -->
  <section>
    <h2>Conexión</h2>
    <div class="field-row">
      <label for="backend-url">Backend URL</label>
      <div class="input-group">
        <input
          id="backend-url"
          type="text"
          bind:value={backendURL}
          on:blur={saveBackendURL}
          placeholder="http://localhost:8080"
        />
        <button class="btn-sm" on:click={() => { saveBackendURL(); testConnection(); }}>
          {testStatus === 'testing' ? '…' : 'Test'}
        </button>
      </div>
      {#if testStatus === 'ok'}
        <span class="status-ok">{testMsg}</span>
      {:else if testStatus === 'error'}
        <span class="status-err">{testMsg}</span>
      {/if}
    </div>
    <p class="hint">Se guarda en localStorage. Útil cuando el backend corre en otra IP (LAN, VPS).</p>
  </section>

  <!-- ─── Section CF Clearance ─── -->
  <section>
    <h2>Cloudflare Clearance</h2>
    <p class="hint">Necesaria para sincronizar el catálogo (Browse). Copia el valor de la cookie <code>cf_clearance</code> desde khinsider.com en tu browser (DevTools → Application → Cookies).</p>
    <div class="field-row" style="margin-top:10px">
      <div class="input-group">
        <input
          type="password"
          placeholder="Pega aquí el valor de cf_clearance…"
          bind:value={cfValue}
          on:keydown={e => e.key === 'Enter' && saveCF()}
        />
        <button class="btn-sm" on:click={saveCF} disabled={!cfValue.trim()}>Guardar</button>
      </div>
      {#if cfStatus === 'ok'}<span class="status-ok">Cookie enviada al backend</span>{/if}
      {#if cfStatus === 'error'}<span class="status-err">Error al enviar</span>{/if}
    </div>
  </section>

  <!-- ─── Section 2: Downloaded albums ─── -->
  <section>
    <h2>Álbumes descargados</h2>
    {#if dlLoading}
      <p class="muted">Cargando…</p>
    {:else if dlAlbums.length === 0}
      <p class="muted">Ningún álbum tiene tracks descargados localmente.</p>
    {:else}
      <div class="dl-list">
        {#each dlAlbums as a}
          <div class="dl-row">
            <button class="cover-btn" on:click={() => goto(`/albums/${a.id}`)}>
              <CoverImage url={a.coverUrl} title={a.title} size={40} radius={5} />
            </button>
            <div class="dl-info">
              <button class="dl-title" on:click={() => goto(`/albums/${a.id}`)}>{a.title}</button>
              <span class="dl-meta">
                {a.downloaded}/{a.trackCount} tracks · {fmtBytes(a.diskBytes)}
                {#if a.platform} · {a.platform}{/if}
                {#if a.year} · {a.year}{/if}
              </span>
            </div>
            <button
              class="btn-del"
              disabled={deleting.has(a.id)}
              on:click={() => deleteLocal(a)}
            >
              {deleting.has(a.id) ? '…' : 'Eliminar'}
            </button>
          </div>
        {/each}
      </div>
    {/if}
  </section>

  <!-- ─── Section 3: Library stats + scrape pending ─── -->
  <section>
    <h2>Biblioteca</h2>
    {#if statsLoading}
      <p class="muted">Cargando…</p>
    {:else if stats}
      <div class="stats-grid">
        <div class="stat"><span class="stat-val">{stats.albums}</span><span class="stat-lbl">álbumes</span></div>
        <div class="stat"><span class="stat-val">{stats.tracks}</span><span class="stat-lbl">tracks</span></div>
        <div class="stat"><span class="stat-val">{stats.scraped}</span><span class="stat-lbl">resueltos</span></div>
        <div class="stat"><span class="stat-val">{stats.downloaded}</span><span class="stat-lbl">locales</span></div>
        <div class="stat stat-pending"><span class="stat-val">{stats.pending}</span><span class="stat-lbl">pendientes</span></div>
      </div>

      {#if stats.pending > 0}
        <div class="scrape-row">
          <span class="muted">{stats.pending} tracks sin URL resuelta</span>
          <button class="btn-scrape" disabled={scraping} on:click={scrapeAllPending}>
            {scraping ? 'Scrapeando…' : 'Scrapear todo'}
          </button>
        </div>
        {#if scrapeResult}
          <p class="scrape-result">
            Resueltos: <strong>{scrapeResult.resolved}</strong> ·
            Fallidos: <strong>{scrapeResult.failed}</strong> de {scrapeResult.total}
          </p>
        {/if}
      {:else}
        <p class="status-ok">Todos los tracks tienen URL resuelta.</p>
      {/if}
    {/if}
  </section>
</div>

<style>
  .page { padding: var(--sp-md); max-width: 720px; }
  h1 { font-size: 22px; font-weight: 700; margin-bottom: 24px; }

  section { margin-bottom: 36px; }
  h2 { font-size: 14px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.06em;
       color: var(--text-muted); margin-bottom: 14px; border-bottom: 1px solid var(--separator); padding-bottom: 6px; }

  .field-row { display: flex; flex-direction: column; gap: 6px; }
  label { font-size: 13px; color: var(--text-sec); }
  .input-group { display: flex; gap: 8px; }
  input[type="text"] {
    flex: 1; background: var(--bg-input, rgba(255,255,255,0.06)); border: 1px solid var(--separator);
    border-radius: var(--r-md); padding: 7px 10px; font-size: 13px; color: var(--text);
    font-family: monospace;
  }
  input[type="text"]:focus { outline: none; border-color: var(--accent); }
  .btn-sm {
    padding: 7px 14px; background: var(--accent-soft); color: var(--accent);
    border-radius: var(--r-md); font-size: 13px; font-weight: 600; white-space: nowrap;
  }
  .btn-sm:hover { background: rgba(203,168,39,0.18); }
  .hint { font-size: 12px; color: var(--text-muted); margin-top: 4px; }
  .status-ok { font-size: 12px; color: #4ade80; }
  .status-err { font-size: 12px; color: #f87171; }
  .muted { color: var(--text-muted); font-size: 13px; }

  /* Downloaded albums */
  .dl-list { display: flex; flex-direction: column; gap: 2px; }
  .dl-row {
    display: flex; align-items: center; gap: 12px;
    padding: 8px; border-radius: var(--r-md); transition: background 0.1s;
  }
  .dl-row:hover { background: rgba(255,255,255,0.04); }
  .cover-btn { flex-shrink: 0; border-radius: 5px; overflow: hidden; }
  .dl-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
  .dl-title { text-align: left; font-size: 13px; font-weight: 500; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .dl-title:hover { color: var(--accent); }
  .dl-meta { font-size: 11px; color: var(--text-muted); }
  .btn-del {
    padding: 5px 12px; font-size: 12px; color: #f87171;
    border: 1px solid rgba(248,113,113,0.3); border-radius: var(--r-md);
    transition: background 0.1s; flex-shrink: 0;
  }
  .btn-del:hover:not(:disabled) { background: rgba(248,113,113,0.1); }
  .btn-del:disabled { opacity: 0.4; cursor: not-allowed; }

  /* Stats */
  .stats-grid { display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 16px; }
  .stat { display: flex; flex-direction: column; align-items: center; gap: 2px;
          background: rgba(255,255,255,0.04); border-radius: var(--r-md); padding: 12px 16px; min-width: 80px; }
  .stat-val { font-size: 22px; font-weight: 700; color: var(--text); }
  .stat-lbl { font-size: 11px; color: var(--text-muted); }
  .stat-pending .stat-val { color: var(--accent); }

  .scrape-row { display: flex; align-items: center; gap: 12px; }
  .btn-scrape {
    padding: 7px 16px; background: var(--accent-soft); color: var(--accent);
    border-radius: var(--r-md); font-size: 13px; font-weight: 600;
  }
  .btn-scrape:hover:not(:disabled) { background: rgba(203,168,39,0.18); }
  .btn-scrape:disabled { opacity: 0.4; cursor: not-allowed; }
  .scrape-result { font-size: 13px; color: var(--text-sec); margin-top: 8px; }
</style>
