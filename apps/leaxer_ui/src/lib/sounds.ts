/**
 * Sound effects using HTML Audio
 */

// Available sound files
export const AVAILABLE_SOUNDS = [
  'Belligerent',
  'Calm',
  'Chord Extended',
  'Chord',
  'Cloud',
  'Doorbell',
  'Enharpment',
  'Flit Flute',
  'Glass',
  'Glass Return',
  'Glisten',
  'Information Bell',
  'Information Block',
  'Jinja',
  'Koto',
  'Modular',
  'Newsflash Bright',
  'Newsflash',
  'Pizza Box',
  'Polite',
  'Ponderous',
  'Reverie',
  'Sharp',
  'Woodblock',
] as const;

export type SoundName = (typeof AVAILABLE_SOUNDS)[number];

// Sound event types
export type SoundEvent = 'start' | 'complete' | 'error' | 'stop' | 'success' | 'return';

// Default sounds for each event
export const DEFAULT_SOUNDS: Record<SoundEvent, SoundName> = {
  start: 'Information Bell',
  complete: 'Enharpment',
  error: 'Ponderous',
  stop: 'Pizza Box',
  success: 'Information Block',
  return: 'Glass Return',
};

// Audio cache to avoid reloading
const audioCache: Map<string, HTMLAudioElement> = new Map();

// Volume (0-1)
let globalVolume = 0.5;
let soundsEnabled = true;

/**
 * Set global volume for all sounds
 */
export function setVolume(volume: number): void {
  globalVolume = Math.max(0, Math.min(1, volume));
}

/**
 * Get current volume
 */
export function getVolume(): number {
  return globalVolume;
}

/**
 * Enable or disable sounds
 */
export function setSoundsEnabled(enabled: boolean): void {
  soundsEnabled = enabled;
}

/**
 * Check if sounds are enabled
 */
export function isSoundsEnabled(): boolean {
  return soundsEnabled;
}

/**
 * Get or create audio element for a sound
 */
function getAudio(soundName: SoundName): HTMLAudioElement {
  const cached = audioCache.get(soundName);
  if (cached) return cached;

  const audio = new Audio(`/sounds/${soundName}.ogg`);
  audio.preload = 'auto';
  audioCache.set(soundName, audio);
  return audio;
}

/**
 * Play a sound by name
 */
export function playSound(soundName: SoundName): void {
  if (!soundsEnabled) return;

  try {
    const audio = getAudio(soundName);
    audio.volume = globalVolume;
    audio.currentTime = 0;
    audio.play().catch((e) => {
      console.warn('Could not play sound:', e);
    });
  } catch (e) {
    console.warn('Error playing sound:', e);
  }
}

/**
 * Preload all sounds for faster playback
 */
export function preloadSounds(): void {
  AVAILABLE_SOUNDS.forEach((name) => {
    getAudio(name);
  });
}

// Legacy functions for compatibility - these now use the settings store
// The actual sound selection comes from settingsStore

let soundSettings: Record<SoundEvent, SoundName> = { ...DEFAULT_SOUNDS };

/**
 * Update sound settings (called from settings store)
 */
export function updateSoundSettings(settings: Record<SoundEvent, SoundName>): void {
  soundSettings = { ...settings };
}

/**
 * Unlock audio on user interaction (for browser autoplay policy)
 */
export function unlockAudio(): void {
  // Create and play a silent audio to unlock
  const audio = new Audio();
  audio.volume = 0;
  audio.play().catch(() => {});
}

/**
 * Play start sound
 */
export function playStartSound(): void {
  playSound(soundSettings.start);
}

/**
 * Play completion sound
 */
export function playCompleteSound(): void {
  playSound(soundSettings.complete);
}

/**
 * Play error sound
 */
export function playErrorSound(): void {
  playSound(soundSettings.error);
}

/**
 * Play stop/abort sound
 */
export function playStopSound(): void {
  playSound(soundSettings.stop);
}

/**
 * Play success sound
 */
export function playSuccessSound(): void {
  playSound(soundSettings.success);
}

/**
 * Play return sound (chat response completed)
 */
export function playReturnSound(): void {
  playSound(soundSettings.return);
}
