<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { api } from '$lib/api';
  import { currentUser } from '$lib/stores/auth';
  import { requireAuth } from '$lib/stores/authModal';
  import { addToast } from '$lib/stores/toasts';

  export let albumId: string;
  export let favorited = false;

  const dispatch = createEventDispatcher<{ change: boolean }>();

  let loading = false;

  async function doToggle() {
    if (loading) return;
    loading = true;
    try {
      const res = await api.toggleFavorite(albumId);
      favorited = res.favorited;
      dispatch('change', favorited);
      addToast(favorited ? 'Añadido a favoritos' : 'Eliminado de favoritos');
    } catch {
      addToast('Error al actualizar favoritos', 'error');
    } finally {
      loading = false;
    }
  }

  function toggle(e: MouseEvent) {
    e.stopPropagation();
    if (!$currentUser) {
      requireAuth(doToggle);
      return;
    }
    doToggle();
  }
</script>

<button
  class="fav-btn"
  class:active={favorited}
  class:loading
  on:click={toggle}
  title={favorited ? 'Quitar de favoritos' : 'Añadir a favoritos'}
  aria-label={favorited ? 'Quitar de favoritos' : 'Añadir a favoritos'}
>
  ★
</button>

<style>
  .fav-btn {
    font-size: 16px;
    color: var(--text-muted);
    opacity: 0.5;
    transition: color 0.15s, opacity 0.15s, transform 0.1s;
    line-height: 1;
  }
  .fav-btn:hover { color: var(--accent); opacity: 1; transform: scale(1.1); }
  .fav-btn.active { color: var(--accent); opacity: 1; }
  .fav-btn.loading { opacity: 0.4; cursor: default; }
</style>
