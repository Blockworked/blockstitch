// Live dict-name choices shared by real and palette value blocks. The
// reactive arrays stay stable so registered operator specs (see
// `./dictOperators`) see updates when a dict is created, renamed, or
// deleted. The palette initializes before backend state arrives, so both
// arrays need a usable first option immediately.
import { reactive } from 'vue';
import type { DictNameOption } from './dictOperators';

export const DICT_NAME_OPTIONS = reactive<DictNameOption[]>([{ value: '', label: 'dict' }]);
export const DICT_EMPTY_OPTIONS = reactive<DictNameOption[]>([{ value: '', label: 'dict' }]);

export function setDictNameOptions(names: string[]): void {
  const choices = names.length ? names : [''];
  DICT_NAME_OPTIONS.splice(
    0,
    DICT_NAME_OPTIONS.length,
    ...choices.map(name => ({ value: name, label: name || 'dict' })),
  );
  DICT_EMPTY_OPTIONS.splice(
    0,
    DICT_EMPTY_OPTIONS.length,
    ...choices.map(name => ({ value: name, label: name || 'dict' })),
  );
}
