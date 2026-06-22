<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { playlists, addTrackToPlaylist, createPlaylist } from '$lib/stores/playlists';
  import { currentUser } from '$lib/stores/auth';
  import { addToast } from '$lib/stores/toasts';

  export let open = false;
  export let trackId = '';

  const dispatch = createEventDispatcher<{ close: void }>();

  let newName = '';
  let creating = false;

  function close() {
    open = false;
    newName = '';
    dispatch('close');
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') close();
  }

  async function addTo(playlistId: string, playlistName: string) {
    try {
      await addTrackToPlaylist(playlistId, trackId);
      addToast(`Added to "${playlistName}"`);
      close();
    } catch (err: any) {
      if (err.message?.includes('already in playlist') || err.message?.includes('Conflict')) {
        addToast('Track already in playlist', 'error');
      } else {
        addToast(err.message ?? 'Error', 'error');
      }
    }
  }

  async function createAndAdd() {
    if (!newName.trim()) return;
    creating = true;
    try {
      const pl = await createPlaylist(newName.trim());
      await addTrackToPlaylist(pl.id, trackId);
      addToast(`Added to "${pl.name}"`);
      close();
    } catch (err: any) {
      addToast(err.message ?? 'Error', 'error');
    } finally {
      creating = false;
    }
  }

  $: myLists = $currentUser ? $playlists.filter(p => p.ownerId === $currentUser!.id) : [];
</script>

<svelte:window on:keydown={onKeydown} />

{#if open}
  <div class="backdrop" on:click={close} role="presentation">
    <div class="modal" on:click|stopPropagation role="dialog" aria-modal="true">
      <h2>Add to playlist</h2>

      {#if myLists.length > 0}
        <ul class="list">
          {#each myLists as pl}
            <li>
              <button on:click={() => addTo(pl.id, pl.name)}>
                <span class="name">{pl.name}</span>
                <span class="count">{pl.trackCount} tracks</span>
              </button>
            </li>
          {/each}
        </ul>
      {:else}
        <p class="empty">No playlists yet.</p>
      {/if}

      <div class="new-row">
        <input bind:value={newName} placeholder="New playlist name…" maxlength="100"
          on:keydown={e => e.key === 'Enter' && createAndAdd()} />
        <button class="create-btn" on:click={createAndAdd} disabled={creating || !newName.trim()}>
          {creating ? '…' : '+'}
        </button>
      </div>

      <button class="cancel" on:click={close}>Cancel</button>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed; inset: 0;
    background: rgba(0,0,0,0.6);
    display: flex; align-items: center; justify-content: center;
    z-index: 200;
  }
  .modal {
    background: var(--surface);
    border: 1px solid var(--separator);
    border-radius: var(--r-lg);
    padding: 24px;
    width: 360px;
    max-width: 90vw;
    display: flex; flex-direction: column; gap: 16px;
  }
  h2 { font-size: 16px; font-weight: 700; }
  .list { list-style: none; display: flex; flex-direction: column; gap: 2px; max-height: 280px; overflow-y: auto; }
  .list li button {
    width: 100%; display: flex; justify-content: space-between; align-items: center;
    padding: 9px 12px;
    border-radius: var(--r-md);
    font-size: 13px;
    text-align: left;
  }
  .list li button:hover { background: var(--surface-hi); }
  .name { color: var(--text); }
  .count { color: var(--text-sec); font-size: 11px; }
  .empty { color: var(--text-sec); font-size: 12px; }
  .new-row { display: flex; gap: 8px; }
  .new-row input {
    flex: 1;
    background: var(--muted);
    border: 1px solid var(--separator);
    border-radius: var(--r-sm);
    padding: 8px 10px;
    color: var(--text);
    font: inherit;
    font-size: 13px;
  }
  .new-row input:focus { border-color: var(--accent); outline: none; }
  .create-btn {
    padding: 8px 14px;
    background: var(--accent-soft);
    color: var(--accent);
    border-radius: var(--r-sm);
    font-size: 16px;
    font-weight: 700;
  }
  .create-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .create-btn:not(:disabled):hover { background: rgba(203,168,39,0.18); }
  .cancel {
    align-self: flex-end;
    padding: 6px 14px;
    font-size: 12px;
    color: var(--text-sec);
    border-radius: var(--r-md);
  }
  .cancel:hover { color: var(--text); }
</style>
