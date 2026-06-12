<script lang="ts">
  import { api, pollJob } from '$lib/api';
  import { createEventDispatcher } from 'svelte';

  export let open = false;
  const dispatch = createEventDispatcher<{ done: string; close: void }>();

  let url = '';
  let status: 'idle' | 'loading' | 'done' | 'error' = 'idle';
  let errMsg = '';

  async function submit() {
    if (!url.trim()) return;
    status = 'loading';
    errMsg = '';
    try {
      const job = await api.addAlbum(url.trim());
      if (job.status === 'done') {
        status = 'done';
        dispatch('done', job.albumId);
        setTimeout(close, 800);
        return;
      }
      await pollJob(job.jobId, (albumId) => {
        status = 'done';
        dispatch('done', albumId);
        setTimeout(close, 800);
      });
    } catch (e: unknown) {
      status = 'error';
      errMsg = e instanceof Error ? e.message : String(e);
    }
  }

  function close() {
    open = false;
    url = '';
    status = 'idle';
    errMsg = '';
    dispatch('close');
  }

  function onKey(e: KeyboardEvent) {
    if (e.key === 'Escape') close();
    if (e.key === 'Enter') submit();
  }
</script>

{#if open}
  <div class="overlay" on:click|self={close} role="dialog" aria-modal="true">
    <div class="modal">
      <div class="header">
        <span>Add Album</span>
        <button on:click={close}>✕</button>
      </div>
      <div class="body">
        <label for="url-input">Paste khinsider album URL</label>
        <input
          id="url-input"
          type="url"
          placeholder="https://downloads.khinsider.com/..."
          bind:value={url}
          on:keydown={onKey}
          disabled={status === 'loading'}
          autofocus
        />
        {#if status === 'error'}
          <p class="err">{errMsg}</p>
        {/if}
        {#if status === 'done'}
          <p class="ok">✓ Album added!</p>
        {/if}
      </div>
      <div class="footer">
        <button class="cancel" on:click={close}>Cancel</button>
        <button class="add" on:click={submit} disabled={status === 'loading' || !url.trim()}>
          {status === 'loading' ? 'Scraping…' : 'Add'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed; inset: 0;
    background: rgba(0,0,0,0.55);
    display: flex; align-items: center; justify-content: center;
    z-index: 500;
  }
  .modal {
    background: var(--surface);
    border: 1px solid var(--separator);
    border-radius: var(--r-lg);
    width: 420px;
    display: flex;
    flex-direction: column;
  }
  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 14px 16px;
    border-bottom: 1px solid var(--separator);
    font-weight: 600;
  }
  .body {
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
  }
  label { font-size: 12px; color: var(--text-sec); }
  input {
    width: 100%;
    padding: 8px 10px;
    background: rgba(255,255,255,0.06);
    border: 1px solid var(--separator);
    border-radius: var(--r-sm);
    font-size: 13px;
    color: var(--text);
  }
  input:focus { border-color: var(--accent); }
  .err { font-size: 12px; color: var(--red); }
  .ok { font-size: 12px; color: #4caf50; }
  .footer {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    padding: 12px 16px;
    border-top: 1px solid var(--separator);
  }
  .cancel {
    padding: 7px 14px;
    border-radius: var(--r-sm);
    font-size: 13px;
    color: var(--text-sec);
  }
  .cancel:hover { color: var(--text); }
  .add {
    padding: 7px 16px;
    background: var(--accent);
    color: #131320;
    border-radius: var(--r-sm);
    font-size: 13px;
    font-weight: 600;
  }
  .add:disabled { opacity: 0.5; cursor: not-allowed; }
</style>
