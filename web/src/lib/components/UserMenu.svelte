<script lang="ts">
  import { currentUser, logout } from '$lib/stores/auth';
  import { api } from '$lib/api';

  export let onLogin: () => void = () => {};
  export let collapsed = false;

  let open = false;
  let btnEl: HTMLButtonElement;
  let dropdownStyle = '';

  function toggle() {
    open = !open;
    if (open && btnEl) {
      const r = btnEl.getBoundingClientRect();
      dropdownStyle = `left:${r.left}px; bottom:${window.innerHeight - r.top + 4}px; min-width:${Math.max(r.width, 180)}px;`;
    }
  }

  function onOutsideClick(e: MouseEvent) {
    if (!(e.target as HTMLElement).closest('.user-menu') && !(e.target as HTMLElement).closest('.dropdown')) open = false;
  }

  async function handleLogout() {
    open = false;
    await logout(api.baseURL());
  }
</script>

<svelte:window on:click={onOutsideClick} on:resize={() => open = false} />

<div class="user-menu">
  {#if $currentUser}
    <button class="user-btn" class:collapsed bind:this={btnEl} on:click={toggle} title={collapsed ? `@${$currentUser.username}` : undefined}>
      <span class="avatar">{$currentUser.username[0].toUpperCase()}</span>
      {#if !collapsed}
        <span class="username">@{$currentUser.username}</span>
        <span class="caret">{open ? '▴' : '▾'}</span>
      {/if}
    </button>
    {#if open}
      <div class="dropdown" style={dropdownStyle}>
        <div class="dropdown-email">{$currentUser.email}</div>
        <button class="dropdown-item logout" on:click={handleLogout}>Cerrar sesión</button>
      </div>
    {/if}
  {:else}
    <button class="login-btn" on:click={onLogin}>{collapsed ? '→' : 'Entrar'}</button>
  {/if}
</div>

<style>
  .user-menu { position: relative; }

  .user-btn {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 6px 8px;
    border-radius: var(--r-md, 8px);
    font-size: 12px;
    color: var(--text-sec);
    width: 100%;
  }
  .user-btn:hover { background: rgba(255,255,255,0.05); color: var(--text); }
  .user-btn.collapsed { justify-content: center; padding: 6px; gap: 0; }

  .avatar {
    width: 22px;
    height: 22px;
    border-radius: 50%;
    background: var(--accent-soft);
    color: var(--accent);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 11px;
    font-weight: 700;
    flex-shrink: 0;
  }
  .username {
    flex: 1;
    text-align: left;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-weight: 600;
    color: var(--text);
  }
  .caret { font-size: 9px; color: var(--text-muted); }

  .dropdown {
    position: fixed;
    background: var(--surface);
    border: 1px solid var(--separator);
    border-radius: var(--r-md, 8px);
    overflow: hidden;
    z-index: 1000;
    box-shadow: 0 4px 16px rgba(0,0,0,0.4);
  }
  .dropdown-email {
    padding: 8px 12px;
    font-size: 11px;
    color: var(--text-muted);
    border-bottom: 1px solid var(--separator);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .dropdown-item {
    display: block;
    width: 100%;
    text-align: left;
    padding: 8px 12px;
    font-size: 13px;
    color: var(--text);
  }
  .dropdown-item:hover { background: rgba(255,255,255,0.05); }
  .logout { color: var(--red, #f87171); }
  .logout:hover { background: rgba(248,113,113,0.1); }

  .login-btn {
    width: 100%;
    padding: 8px 12px;
    background: var(--accent-soft);
    color: var(--accent);
    border-radius: var(--r-md, 8px);
    font-size: 13px;
    font-weight: 600;
    transition: background 0.15s;
  }
  .login-btn:hover { background: rgba(203,168,39,0.18); }
</style>
