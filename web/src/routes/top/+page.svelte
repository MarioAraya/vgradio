<script lang="ts">
  import { onMount } from 'svelte';
  import { api, pollJob } from '$lib/api';
  import CoverImage from '$lib/components/CoverImage.svelte';
  import { addToast } from '$lib/stores/toasts';
  import type { Top12Entry } from '$lib/types';

  const platforms: { id: string; label: string }[] = [
    { id: 'ps1',    label: 'PS1' },
    { id: 'ps2',    label: 'PS2' },
    { id: 'ps3',    label: 'PS3' },
    { id: 'ps4',    label: 'PS4' },
    { id: 'ps5',    label: 'PS5' },
    { id: 'switch', label: 'Switch' },
    { id: 'wii',    label: 'Wii' },
    { id: 'wiiu',   label: 'Wii U' },
    { id: 'n64',    label: 'N64' },
    { id: 'xbox',   label: 'Xbox' },
  ];

  let entries: Record<string, Top12Entry[]> = {};
  let loading: Record<string, boolean> = {};
  let errors: Record<string, string> = {};
  let adding: Record<string, boolean> = {};

  onMount(() => {
    for (const p of platforms) loadPlatform(p.id);
  });

  async function loadPlatform(id: string) {
    loading = { ...loading, [id]: true };
    try {
      entries = { ...entries, [id]: await api.top12(id) };
    } catch (e) {
      errors = { ...errors, [id]: e instanceof Error ? e.message : String(e) };
    } finally {
      loading = { ...loading, [id]: false };
    }
  }

  async function addToLibrary(entry: Top12Entry) {
    if (adding[entry.sourceUrl]) return;
    adding = { ...adding, [entry.sourceUrl]: true };
    try {
      const job = await api.addAlbum(entry.sourceUrl);
      if (job.status === 'done') {
        addToast(`Added "${entry.title}"`);
      } else {
        await pollJob(job.jobId, () => addToast(`Added "${entry.title}"`));
      }
    } catch (e) {
      addToast(e instanceof Error ? e.message : 'Error', 'error');
    } finally {
      adding = { ...adding, [entry.sourceUrl]: false };
    }
  }
</script>

<div class="page">
  <div class="header">
    <h1>Top 12</h1>
    <span class="sub">Los álbumes más populares de khinsider, por plataforma</span>
  </div>

  {#each platforms as p}
    <section class="platform">
      <h2>{p.label}</h2>
      {#if loading[p.id] && !entries[p.id]}
        <div class="row-msg muted">Cargando…</div>
      {:else if errors[p.id]}
        <div class="row-msg err">Error: {errors[p.id]}</div>
      {:else if entries[p.id]}
        <div class="grid">
          {#each entries[p.id] as entry}
            <div class="cover-card">
              <a class="cover-btn" href={entry.sourceUrl} target="_blank" rel="noopener noreferrer" title={`${entry.title} — view on khinsider`}>
                <CoverImage url={entry.coverThumbUrl} title={entry.title} size={140} radius={8} />
              </a>
              <button
                class="add-btn"
                class:adding={adding[entry.sourceUrl]}
                disabled={adding[entry.sourceUrl]}
                on:click={() => addToLibrary(entry)}
                title="Add to library"
              >
                {adding[entry.sourceUrl] ? '…' : '+'}
              </button>
              <span class="title" title={entry.title}>{entry.title}</span>
            </div>
          {/each}
        </div>
      {/if}
    </section>
  {/each}
</div>

<style>
  .page { padding: var(--sp-md); }
  .header { margin-bottom: var(--sp-lg); }
  h1 { font-size: 22px; font-weight: 700; margin-bottom: 4px; }
  .sub { font-size: 12px; color: var(--text-muted); }
  .platform { margin-bottom: 32px; }
  .platform h2 {
    font-size: 15px;
    font-weight: 700;
    color: var(--text);
    padding-bottom: 8px;
    margin-bottom: 12px;
    border-bottom: 1px solid var(--separator);
  }
  .row-msg { font-size: 12px; padding: 8px 0; }
  .muted { color: var(--text-muted); }
  .err { color: var(--red); }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: var(--sp-md);
  }
  .cover-card { position: relative; display: flex; flex-direction: column; gap: 6px; }
  .cover-btn { border-radius: var(--r-md); overflow: hidden; }
  .title {
    font-size: 12px;
    color: var(--text-sec);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .add-btn {
    position: absolute;
    top: 6px;
    right: 6px;
    width: 26px;
    height: 26px;
    border-radius: 50%;
    background: rgba(0,0,0,0.65);
    color: var(--text);
    font-size: 15px;
    font-weight: 600;
    display: flex;
    align-items: center;
    justify-content: center;
    opacity: 0;
    transition: opacity 0.15s, background 0.15s, color 0.15s;
  }
  .cover-card:hover .add-btn { opacity: 1; }
  .add-btn:hover { background: var(--accent); color: var(--on-accent); }
  .add-btn.adding { opacity: 1; cursor: default; }
</style>
