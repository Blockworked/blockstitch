import { ref } from 'vue';

type Theme = 'light' | 'dark';

const STORAGE_KEY = 'blockstitch-theme';
// A host migrating from a pre-blockstitch theme toggle of its own can carry its
// old storage key's value over here once, so an existing user's preference
// survives the switch instead of silently resetting to the dark default.
const LEGACY_STORAGE_KEYS = ['blockwork-theme', 'macros-theme'];

function readStored(): Theme | null {
  try {
    const v = localStorage.getItem(STORAGE_KEY) ?? LEGACY_STORAGE_KEYS.map(k => localStorage.getItem(k)).find(v => v != null) ?? null;
    return v === 'light' || v === 'dark' ? v : null;
  } catch (_e) {
    return null;
  }
}

// Module-level singleton — one theme for the whole app's lifetime.
const currentTheme = ref<Theme>(
  document.documentElement.dataset.theme === 'light' || document.documentElement.dataset.theme === 'dark'
    ? (document.documentElement.dataset.theme as Theme)
    : readStored() ?? 'dark',
);

function apply(theme: Theme) {
  currentTheme.value = theme;
  document.documentElement.dataset.theme = theme;
  try {
    localStorage.setItem(STORAGE_KEY, theme);
  } catch (_e) {
    // ignore (e.g. storage disabled)
  }
}

// Reflect the initial resolved theme onto the DOM immediately, same as
// `apply` does for a later change, so CSS themed off `[data-theme]` matches
// `currentTheme` from first paint.
document.documentElement.dataset.theme = currentTheme.value;

export function useTheme() {
  return {
    currentTheme,
    setTheme: apply,
    toggleTheme: () => apply(currentTheme.value === 'light' ? 'dark' : 'light'),
  };
}
