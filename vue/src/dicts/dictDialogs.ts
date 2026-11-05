// The "Make a Dict" / "Rename Dict" dialog's trigger state. The dialog
// itself is a host component (`MakeDictDialog.vue`); this module only owns
// whether it is open and what it is renaming.
import { reactive } from 'vue';

export const dictDialog = reactive({ open: false, renameTarget: '' });

export function openCreateDictDialog(): void {
  dictDialog.renameTarget = '';
  dictDialog.open = true;
}

export function openRenameDictDialog(name: string): void {
  dictDialog.renameTarget = name;
  dictDialog.open = true;
}

export function closeDictDialog(): void {
  dictDialog.open = false;
  dictDialog.renameTarget = '';
}
