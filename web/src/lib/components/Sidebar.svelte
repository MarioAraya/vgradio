<script lang="ts">
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';

  let showAddURL = false;
  export let onAddURL: () => void = () => {};

  const nav = [
    { href: '/',          label: 'Library',  icon: '♫' },
    { href: '/browse',    label: 'Browse',   icon: '🔍' },
    { href: '/favorites', label: 'Favorites', icon: '★' },
    { href: '/history',   label: 'Recientes', icon: '🕐' },
    { href: '/wishlist',  label: 'Wishlist',  icon: '📋' },
    { href: '/settings', label: 'Settings',  icon: '⚙' },
  ];
</script>

<aside class="sidebar">
  <div class="logo">VGRadio</div>
  <nav>
    {#each nav as item}
      <a href={item.href} class="nav-item" class:active={$page.url.pathname === item.href}>
        <span class="icon">{item.icon}</span>
        <span>{item.label}</span>
      </a>
    {/each}
  </nav>
  <div class="bottom">
    <slot name="user" />
    <button class="add-btn" on:click={onAddURL}>+ Add URL</button>
  </div>
</aside>

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
  }
  .logo {
    padding: 20px 16px 12px;
    font-size: 16px;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.05em;
  }
  nav {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 4px 8px;
  }
  .nav-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 10px;
    border-radius: var(--r-md);
    font-size: 13px;
    color: var(--text-sec);
    transition: background 0.1s, color 0.1s;
  }
  .nav-item:hover { background: rgba(255,255,255,0.04); color: var(--text); }
  .nav-item.active { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
  .icon { font-size: 14px; width: 18px; text-align: center; }
  .bottom {
    padding: 12px;
    border-top: 1px solid var(--separator);
    display: flex;
    flex-direction: column;
    gap: 8px;
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
