export interface AlbumSummary {
  id: string
  title: string
  platform: string
  year: number
  albumType: string
  trackCount: number
  coverUrls: string[]
  isFavorite?: boolean
}

export interface Album {
  id: string
  title: string
  altTitle: string
  platform: string
  year: number
  developer: string
  publisher: string
  catalogNumber: string
  albumType: string
  description: string
  sourceUrl: string
  covers: Cover[]
  tracks: Track[]
  comments: Comment[]
  isFavorite?: boolean
}

export interface Track {
  id: string
  index: number
  name: string
  durationSec: number
  sizeBytes: number
  streamUrl: string
  downloadUrl: string
  scraped?: boolean
  downloaded: boolean
  isFavorite?: boolean
}

export interface Cover { url: string; width: number; height: number }
export interface Comment { author: string; body: string; postedAt: string }

export interface ScrapeJob {
  jobId: string
  albumId: string
  status: 'pending' | 'running' | 'done' | 'failed'
  error?: string
}

export interface CatalogEntry {
  title: string
  sourceUrl: string
  platform: string
  year: number
}

export interface CatalogPage {
  total: number
  offset: number
  limit: number
  items: CatalogEntry[]
}

export interface CatalogConsole {
  id: string
  name: string
  url: string
  albumCount: number
}

export interface CatalogSyncProgress {
  running: boolean
  total: number
  done: number
  errors: number
  entries: number
  consoles: number
}

export interface FavoriteTrack {
  id: string
  name: string
  albumId: string
  albumTitle: string
  platform: string
  year: number
  durationSec: number
  coverUrl?: string
}

export interface WishlistItem { url: string }

export interface LibraryStats {
  albums: number
  tracks: number
  scraped: number
  downloaded: number
  pending: number
}

export interface DownloadedAlbum {
  id: string
  title: string
  platform: string
  year: number
  coverUrl: string
  trackCount: number
  downloaded: number
  diskBytes: number
}

export interface User {
  id: string
  username: string
  email: string
}

export interface HistoryEntry {
  trackId: string
  trackName: string
  albumId: string
  albumTitle: string
  platform: string
  year: number
  coverUrl: string
  playedAt: string
}
