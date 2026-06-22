<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { createPlaylist, updatePlaylist } from '$lib/stores/playlists';
  import { addToast } from '$lib/stores/toasts';
  import type { PlaylistSummary } from '$lib/types';

  export let open = false;
  export let playlist: PlaylistSummary | null = null; // null = create mode

  const dispatch = createEventDispatcher<{ done: PlaylistSummary; close: void }>();

  let name = '';
  let description = '';
  let isPublic = false;
  let loading = false;

  $: if (open) {
    name = playlist?.name ?? '';
    description = playlist?.description ?? '';
    isPublic = playlist?.isPublic ?? false;
  }

  function close() {
    open = false;
    dispatch('close');
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape') close();
  }

  async function save() {
    if (!name.trim()) return;
    loading = true;
    try {
      if (playlist) {
        await updatePlaylist(playlist.id, { name: name.trim(), description: description.trim(), isPublic });
        dispatch('done', { ...playlist, name: name.trim(), description: description.trim(), isPublic });
        addToast('Playlist updated');
      } else {
        const pl = await createPlaylist(name.trim(), description.trim(), isPublic);
        dispatch('done', pl);
        addToast('Playlist created');
      }
      close();
    } catch (err: any) {
      addToast(err.message ?? 'Error', 'error');
    } finally {
      loading = false;
    }
  }
</script>

<svelte:window on:keydown={onKeydown} />

{#if open}
  <div class="backdrop" on:click={close} role="presentation">
    <div class="modal" on:click|stopPropagation role="dialog" aria-modal="true">
      <h2>{playlist ? playlist.name : 'New playlist'}</h2>

      <div class="field">
        <label for="pl-name">Title</label>
        <input id="pl-name" bind:value={name} placeholder="Playlist name" maxlength="100" />
      </div>

      <div class="field">
        <label for="pl-desc">Description</label>
        <input id="pl-desc" bind:value={description} placeholder="Description (optional)" maxlength="500" />
      </div>

      <div class="field">
        <label for="pl-privacy">Privacy</label>
        <select id="pl-privacy" bind:value={isPublic}>
          <option value={false}>Private</option>
          <option value={true}>Public</option>
        </select>
      </div>

      <div class="actions">
        <button class="cancel" on:click={close}>Cancel</button>
        <button class="save" on:click={save} disabled={loading || !name.trim()}>
          {loading ? '…' : 'Save'}
        </button>
      </div>
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
    padding: 28px 24px;
    width: 420px;
    max-width: 90vw;
    display: flex; flex-direction: column; gap: 20px;
  }
  h2 { font-size: 18px; font-weight: 700; color: var(--text); }
  .field { display: flex; flex-direction: column; gap: 6px; }
  label { font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-sec); }
  input, select {
    background: var(--muted);
    border: 1px solid var(--separator);
    border-radius: var(--r-sm);
    color: var(--text);
    font: inherit;
    padding: 8px 10px;
    font-size: 13px;
  }
  input:focus, select:focus { border-color: var(--accent); outline: none; }
  select option { background: var(--surface); }
  .actions { display: flex; justify-content: flex-end; gap: 10px; padding-top: 4px; }
  .cancel {
    padding: 8px 18px;
    border-radius: var(--r-md);
    font-size: 13px;
    color: var(--text-sec);
  }
  .cancel:hover { color: var(--text); }
  .save {
    padding: 8px 20px;
    background: var(--accent);
    color: #000;
    border-radius: var(--r-md);
    font-size: 13px;
    font-weight: 600;
  }
  .save:disabled { opacity: 0.4; cursor: not-allowed; }
  .save:not(:disabled):hover { opacity: 0.88; }
</style>
