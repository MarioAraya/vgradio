<script lang="ts">
  import { wishlist } from '$lib/stores/wishlist';
  import { api, pollJob } from '$lib/api';
  import { slugToTitle } from '$lib/utils';

  let newUrl = '';
  let importing: Record<string, 'idle' | 'loading' | 'done' | 'error'> = {};

  async function importItem(url: string) {
    importing[url] = 'loading';
    try {
      const job = await api.addAlbum(url);
      if (job.status === 'done') { importing[url] = 'done'; return; }
      await pollJob(job.jobId, () => { importing[url] = 'done'; });
    } catch {
      importing[url] = 'error';
    }
  }

  function add() {
    if (newUrl.trim()) { wishlist.add(newUrl.trim()); newUrl = ''; }
  }
</script>

<div class="page">
  <h1>Wishlist</h1>
  <div class="add-row">
    <input type="url" placeholder="https://downloads.khinsider.com/..." bind:value={newUrl} on:keydown={e => e.key === 'Enter' && add()} />
    <button class="add-btn" on:click={add} disabled={!newUrl.trim()}>Add</button>
  </div>

  {#if $wishlist.length === 0}
    <div class="empty">
      <span class="icon">📋</span>
      <p class="muted">Wishlist is empty</p>
    </div>
  {:else}
    <div class="list">
      {#each $wishlist as item}
        {@const status = importing[item.url] ?? 'idle'}
        <div class="row">
          <span class="item-title">{slugToTitle(item.url)}</span>
          <div class="actions">
            {#if status === 'done'}
              <span class="check">✓ Imported</span>
            {:else if status === 'loading'}
              <span class="muted">Importing…</span>
            {:else if status === 'error'}
              <span class="err">Failed</span>
            {:else}
              <button class="import-btn" on:click={() => importItem(item.url)}>Import</button>
            {/if}
            <button class="rm" on:click={() => wishlist.remove(item.url)}>✕</button>
          </div>
        </div>
      {/each}
    </div>
  {/if}
</div>

<style>
  .page { padding: var(--sp-md); }
  h1 { font-size: 22px; font-weight: 700; margin-bottom: 16px; }
  .add-row { display: flex; gap: 8px; margin-bottom: 20px; }
  .add-row input {
    flex: 1; padding: 8px 12px;
    background: rgba(255,255,255,0.06);
    border: 1px solid var(--separator);
    border-radius: var(--r-sm);
    font-size: 13px; color: var(--text);
  }
  .add-row input:focus { border-color: var(--accent); }
  .add-btn {
    padding: 8px 16px;
    background: var(--accent);
    color: #131320;
    border-radius: var(--r-sm);
    font-size: 13px;
    font-weight: 600;
  }
  .add-btn:disabled { opacity: 0.4; }
  .empty { display: flex; flex-direction: column; align-items: center; gap: 8px; min-height: 200px; justify-content: center; }
  .icon { font-size: 36px; opacity: 0.4; }
  .muted { color: var(--text-muted); font-size: 13px; }
  .list { display: flex; flex-direction: column; gap: 4px; }
  .row {
    display: flex; align-items: center;
    padding: 8px 10px;
    border-radius: var(--r-sm);
    transition: background 0.1s;
  }
  .row:hover { background: rgba(255,255,255,0.04); }
  .item-title { flex: 1; font-size: 13px; color: var(--text); }
  .actions { display: flex; align-items: center; gap: 8px; }
  .import-btn {
    font-size: 12px; color: var(--accent);
    padding: 4px 10px;
    background: var(--accent-soft);
    border-radius: var(--r-sm);
  }
  .check { font-size: 12px; color: #4caf50; }
  .err { font-size: 12px; color: var(--red); }
  .rm { font-size: 12px; color: var(--text-muted); opacity: 0; }
  .row:hover .rm { opacity: 1; }
  .rm:hover { color: var(--red); }
</style>
