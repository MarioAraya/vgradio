<script lang="ts">
  import { page } from '$app/stores';
  import { currentUser } from '$lib/stores/auth';
  import { playlists, loadPlaylists, addTrackToPlaylist, deletePlaylist } from '$lib/stores/playlists';
  import PlaylistEditModal from '$lib/components/PlaylistEditModal.svelte';
  import ContextMenu from '$lib/components/ContextMenu.svelte';
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';
  import { api } from '$lib/api';
  import { addToast } from '$lib/stores/toasts';
  import { hasDragPayload, getDragPayload } from '$lib/dnd';
  import type { PlaylistSummary } from '$lib/types';

  export let onAddURL: () => void = () => {};

  let editOpen = false;
  let renameOpen = false;
  let renamingPlaylist: PlaylistSummary | null = null;
  let collapsed = false;
  let dropTargetId: string | null = null;
  let plCtxMenu: { x: number; y: number; pl: PlaylistSummary } | null = null;

  function openPlaylistContextMenu(e: MouseEvent, pl: PlaylistSummary) {
    e.preventDefault();
    plCtxMenu = { x: e.clientX, y: e.clientY, pl };
  }

  async function deletePlaylistConfirm(pl: PlaylistSummary) {
    if (!confirm(`Delete "${pl.name}"? This can't be undone.`)) return;
    try {
      await deletePlaylist(pl.id);
      if ($page.url.pathname === `/playlists/${pl.id}`) goto('/');
    } catch (e) {
      addToast(e instanceof Error ? e.message : 'Error', 'error');
    }
  }

  function onDragOver(e: DragEvent, playlistId: string) {
    if (!hasDragPayload(e)) return;
    e.preventDefault();
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy';
    dropTargetId = playlistId;
  }

  function onDragLeave(playlistId: string) {
    if (dropTargetId === playlistId) dropTargetId = null;
  }

  async function onDrop(e: DragEvent, playlistId: string, playlistName: string) {
    e.preventDefault();
    dropTargetId = null;
    const payload = getDragPayload(e);
    if (!payload) return;
    try {
      let trackIds: string[];
      if ('trackIds' in payload) {
        trackIds = payload.trackIds;
      } else {
        const album = await api.album(payload.albumId);
        trackIds = album.tracks.map(t => t.id);
      }
      if (!trackIds.length) return;
      await Promise.all(trackIds.map(id => addTrackToPlaylist(playlistId, id)));
      addToast(trackIds.length > 1 ? `Added ${trackIds.length} tracks to "${playlistName}"` : `Added to "${playlistName}"`);
    } catch (err) {
      addToast(err instanceof Error ? err.message : 'Error', 'error');
    }
  }

  onMount(() => {
    collapsed = localStorage.getItem('vgradio.sidebar.collapsed') === '1';
  });

  function toggleCollapse() {
    collapsed = !collapsed;
    localStorage.setItem('vgradio.sidebar.collapsed', collapsed ? '1' : '0');
  }

  const nav = [
    { href: '/',          label: 'Library',   icon: '♫' },
    { href: '/browse',    label: 'Browse',    icon: '🔍' },
    { href: '/top',       label: 'Top 12',    icon: '🏆' },
    { href: '/history',   label: 'Recientes', icon: '🕐' },
    { href: '/settings',  label: 'Settings',  icon: '⚙' },
  ];

  $: if ($currentUser) loadPlaylists();

  $: myPlaylists = $currentUser
    ? $playlists.filter(p => p.ownerId === $currentUser!.id)
    : [];

  function isActive(href: string) {
    return $page.url.pathname === href;
  }
</script>

<aside class="sidebar" class:collapsed>
  <div class="header">
    <button class="hamburger" on:click={toggleCollapse} aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'} title={collapsed ? 'Expand' : 'Collapse'}>
      <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
        <rect y="2"  width="16" height="1.5" rx="0.75"/>
        <rect y="7"  width="16" height="1.5" rx="0.75"/>
        <rect y="12" width="16" height="1.5" rx="0.75"/>
      </svg>
    </button>
    {#if !collapsed}
      <span class="logo-text">VGRadio</span>
    {/if}
  </div>
  <nav>
    {#each nav as item}
      <a href={item.href} class="nav-item" class:active={isActive(item.href)} title={collapsed ? item.label : undefined}>
        <span class="icon">{item.icon}</span>
        {#if !collapsed}<span>{item.label}</span>{/if}
      </a>
    {/each}
  </nav>

  {#if $currentUser && !collapsed}
    <div class="playlists-section">
      <div class="section-header">
        <span class="section-label">Playlists</span>
        <button class="new-pl-icon" title="New playlist" on:click={() => (editOpen = true)}>+</button>
      </div>

      <a href="/playlists/liked" class="nav-item pl-item"
        class:active={$page.url.pathname === '/playlists/liked'}>
        <span class="icon">★</span>
        <div class="pl-info">
          <span class="pl-name">Liked Music</span>
          <span class="pl-sub">Auto playlist</span>
        </div>
      </a>

      {#each myPlaylists as pl}
        <a href="/playlists/{pl.id}" class="nav-item pl-item"
          class:active={$page.url.pathname === `/playlists/${pl.id}`}
          class:drop-target={dropTargetId === pl.id}
          on:dragover={(e) => onDragOver(e, pl.id)}
          on:dragleave={() => onDragLeave(pl.id)}
          on:drop={(e) => onDrop(e, pl.id, pl.name)}
          on:contextmenu={(e) => openPlaylistContextMenu(e, pl)}>
          <span class="icon">♪</span>
          <div class="pl-info">
            <span class="pl-name">{pl.name}</span>
            <span class="pl-sub">{pl.trackCount} tracks</span>
          </div>
        </a>
      {/each}

      <button class="new-pl-btn" on:click={() => (editOpen = true)}>
        <span>+</span> New playlist
      </button>
    </div>
  {/if}

  {#if $currentUser && collapsed}
    <div class="collapsed-playlists">
      <a href="/playlists/liked" class="nav-item" class:active={$page.url.pathname === '/playlists/liked'} title="Liked Music">
        <span class="icon">★</span>
      </a>
    </div>
  {/if}

  <div class="bottom" class:bottom-collapsed={collapsed}>
    <slot name="user" {collapsed} />
    {#if !collapsed}
      <button class="add-btn" on:click={onAddURL}>+ Add URL</button>
    {/if}
  </div>
</aside>

<PlaylistEditModal bind:open={editOpen} playlist={null}
  on:done={e => goto(`/playlists/${e.detail.id}`)} />

<PlaylistEditModal bind:open={renameOpen} playlist={renamingPlaylist}
  on:done={() => renamingPlaylist = null}
  on:close={() => renamingPlaylist = null} />

{#if plCtxMenu}
  <ContextMenu x={plCtxMenu.x} y={plCtxMenu.y} onClose={() => plCtxMenu = null}>
    <button on:click={() => { renamingPlaylist = plCtxMenu!.pl; renameOpen = true; plCtxMenu = null; }}>✏ Rename…</button>
    <div class="divider"></div>
    <button on:click={() => { deletePlaylistConfirm(plCtxMenu!.pl); plCtxMenu = null; }}>🗑 Delete Playlist</button>
  </ContextMenu>
{/if}

<style>
  .sidebar {
    width: var(--sidebar-w);
    min-width: var(--sidebar-w);
    height: 100%;
    background: var(--sidebar);
    border-right: 1px solid var(--separator);
    display: flex;
    flex-direction: column;
    flex-shrink: 0;
    overflow-y: auto;
    overflow-x: hidden;
    transition: width 0.2s ease, min-width 0.2s ease;
  }
  .sidebar.collapsed {
    width: 48px;
    min-width: 48px;
  }
  .header {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 16px 12px 10px;
    flex-shrink: 0;
  }
  .hamburger {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 26px;
    height: 26px;
    border-radius: var(--r-sm);
    color: var(--text-sec);
    flex-shrink: 0;
    transition: background 0.1s, color 0.1s;
  }
  .hamburger:hover { background: var(--hover-md); color: var(--text); }
  .logo-text {
    font-size: 16px;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.05em;
    white-space: nowrap;
  }
  nav {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 4px 8px;
  }
  .sidebar.collapsed nav { padding: 4px 6px; }
  .nav-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 10px;
    border-radius: var(--r-md);
    font-size: 13px;
    color: var(--text-sec);
    transition: background 0.1s, color 0.1s;
    white-space: nowrap;
  }
  .sidebar.collapsed .nav-item { justify-content: center; padding: 8px 6px; gap: 0; }
  .nav-item:hover { background: var(--hover); color: var(--text); }
  .nav-item.active { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
  .icon { font-size: 14px; width: 18px; text-align: center; flex-shrink: 0; }

  .playlists-section {
    border-top: 1px solid var(--separator);
    padding: 8px 8px 4px;
    display: flex;
    flex-direction: column;
    gap: 1px;
    flex: 1;
    min-height: 0;
  }
  .section-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 4px 10px 6px;
  }
  .section-label {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-sec);
    font-weight: 600;
  }
  .new-pl-icon {
    font-size: 18px;
    color: var(--text-sec);
    width: 22px;
    height: 22px;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--r-sm);
  }
  .new-pl-icon:hover { color: var(--text); background: var(--hover-md); }

  .pl-item { align-items: flex-start; padding: 6px 10px; }
  .pl-info { display: flex; flex-direction: column; min-width: 0; }
  .pl-name { font-size: 13px; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .pl-sub { font-size: 10px; color: var(--text-sec); }
  .nav-item.active .pl-name { color: var(--accent); }
  .nav-item.drop-target { background: var(--accent-soft); outline: 1.5px solid var(--accent); outline-offset: -1.5px; }

  .new-pl-btn {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 7px 10px;
    font-size: 12px;
    color: var(--text-sec);
    border-radius: var(--r-md);
    margin-top: 4px;
  }
  .new-pl-btn:hover { background: var(--hover); color: var(--text); }

  .collapsed-playlists {
    padding: 4px 6px;
    display: flex;
    flex-direction: column;
    gap: 2px;
    border-top: 1px solid var(--separator);
  }
  .bottom {
    padding: 12px;
    border-top: 1px solid var(--separator);
    display: flex;
    flex-direction: column;
    gap: 8px;
    flex-shrink: 0;
  }
  .bottom-collapsed {
    padding: 8px 6px;
    align-items: center;
  }
  .add-btn {
    width: 100%;
    padding: 8px 12px;
    background: var(--accent-soft);
    color: var(--accent);
    border-radius: var(--r-md);
    font-size: 13px;
    font-weight: 600;
    transition: background 0.15s;
  }
  .add-btn:hover { background: var(--accent-hi); }
</style>
