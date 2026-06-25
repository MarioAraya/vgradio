<script lang="ts">
  import { page } from '$app/stores';
  import { currentUser } from '$lib/stores/auth';
  import { playlists, loadPlaylists } from '$lib/stores/playlists';
  import PlaylistEditModal from '$lib/components/PlaylistEditModal.svelte';
  import { goto } from '$app/navigation';
  import { onMount } from 'svelte';

  export let onAddURL: () => void = () => {};

  let editOpen = false;
  let collapsed = false;

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
    { href: '/history',   label: 'Recientes', icon: '🕐' },
    { href: '/wishlist',  label: 'Wishlist',  icon: '📋' },
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
          class:active={$page.url.pathname === `/playlists/${pl.id}`}>
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
    {#if !collapsed}
      <slot name="user" />
      <button class="add-btn" on:click={onAddURL}>+ Add URL</button>
    {:else}
      <slot name="user" />
    {/if}
  </div>
</aside>

<PlaylistEditModal bind:open={editOpen} playlist={null}
  on:done={e => goto(`/playlists/${e.detail.id}`)} />

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
  .hamburger:hover { background: rgba(255,255,255,0.07); color: var(--text); }
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
  .nav-item:hover { background: rgba(255,255,255,0.04); color: var(--text); }
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
  .new-pl-icon:hover { color: var(--text); background: rgba(255,255,255,0.06); }

  .pl-item { align-items: flex-start; padding: 6px 10px; }
  .pl-info { display: flex; flex-direction: column; min-width: 0; }
  .pl-name { font-size: 13px; color: var(--text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .pl-sub { font-size: 10px; color: var(--text-sec); }
  .nav-item.active .pl-name { color: var(--accent); }

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
  .new-pl-btn:hover { background: rgba(255,255,255,0.04); color: var(--text); }

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
  .add-btn:hover { background: rgba(203,168,39,0.18); }
</style>
