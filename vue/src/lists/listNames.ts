// Live list-name choices shared by real and palette value blocks. The
// reactive arrays stay stable so registered operator specs (see
// `./listOperators`) see updates when a list is created, renamed, or
// deleted. The palette initializes before backend state arrives, so both
// arrays need a usable first option immediately.
import { reactive } from 'vue';
import type { ListNameOption } from './listOperators';

export const LIST_NAME_OPTIONS = reactive<ListNameOption[]>([{ value: '', label: 'list' }]);
export const LIST_EMPTY_OPTIONS = reactive<ListNameOption[]>([{ value: '', label: 'list' }]);

export function setListNameOptions(names: string[]): void {
  const choices = names.length ? names : [''];
  LIST_NAME_OPTIONS.splice(
    0,
    LIST_NAME_OPTIONS.length,
    ...choices.map(name => ({ value: name, label: name || 'list' })),
  );
  LIST_EMPTY_OPTIONS.splice(
    0,
    LIST_EMPTY_OPTIONS.length,
    ...choices.map(name => ({ value: name, label: name || 'list' })),
  );
}
