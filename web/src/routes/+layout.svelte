<script lang="ts">
  import '../app.css';
  import Sidebar from '$lib/components/Sidebar.svelte';
  import PlayerBar from '$lib/components/PlayerBar.svelte';
  import QueuePanel from '$lib/components/QueuePanel.svelte';
  import AddURLModal from '$lib/components/AddURLModal.svelte';
  import { player } from '$lib/stores/player';
  import { goto } from '$app/navigation';

  let showAddURL = false;

  function handleKeydown(e: KeyboardEvent) {
    const tag = (e.target as HTMLElement).tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA') return;
    if (e.code === 'Space') { e.preventDefault(); player.togglePlay(); }
    if ((e.metaKey || e.ctrlKey) && e.key === '1') { e.preventDefault(); goto('/'); }
    if ((e.metaKey || e.ctrlKey) && e.key === '2') { e.preventDefault(); goto('/browse'); }
    if ((e.metaKey || e.ctrlKey) && e.key === '3') { e.preventDefault(); goto('/favorites'); }
    if ((e.metaKey || e.ctrlKey) && e.key === '4') { e.preventDefault(); showAddURL = true; }
  }
</script>

<svelte:window on:keydown={handleKeydown} />

<div class="shell">
  <div class="main">
    <Sidebar onAddURL={() => showAddURL = true} />
    <div class="content">
      <slot />
    </div>
  </div>
  <PlayerBar />
  <QueuePanel />
  <AddURLModal bind:open={showAddURL} on:done={() => showAddURL = false} />
</div>

<style>
  .shell {
    height: 100vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }
  .main {
    display: flex;
    flex: 1;
    min-height: 0;
    padding-bottom: var(--player-bar-h);
  }
  .content {
    flex: 1;
    overflow-y: auto;
    min-width: 0;
  }
</style>
